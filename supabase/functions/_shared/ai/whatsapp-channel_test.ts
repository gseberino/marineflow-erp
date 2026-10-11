import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDoCmpSubstituido,
  cancelarPendenciaSubstituida,
  checkWhatsAppRateLimit,
  conversaDosComprovantesLigada,
  decidirPendenciaHerdada,
  donoOcupadoParaPerguntar,
  enviarComRegistro,
  formatOptionsAsNumberedText,
  notaDeConfirmacao,
  parseConfirmationReply,
  parseOptionReply,
  pendenciaParaHerdar,
  queueWhatsAppReply,
  registroDoTurno,
  resolveOptionAsUserText,
  resolveOrCreateWhatsAppSession,
  textoDaPendenciaReapresentada,
  textoDaTravaDoComprovante,
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

// 11/10/2026: só a 1ª palavra contava. "Sim ajuste para 2.000,44" com uma pendência viva aprovava o
// pedido COMO ESTAVA e o ajuste se perdia (o dono escreve assim: "Sim envie, primeiro de bom dia…").
Deno.test("parseConfirmationReply: sim com ajuste junto não aprova — vai ao modelo", () => {
  for (const t of ["sim mas manda amanhã", "Sim ajuste para 2.000,44", "ok troca a data para sexta", "1 mas sem o link", "Sim envie, primeiro de bom dia"]) {
    assertEquals(parseConfirmationReply(t), null, t);
  }
});

Deno.test("parseConfirmationReply: sim com cortesia, emoji ou pontuação solta continua aprovando", () => {
  for (const t of ["sim por favor", "sim pode mandar", "Sim 👍", "ok obrigado", "sim por favor!"]) {
    assertEquals(parseConfirmationReply(t), { decision: "approve", pin: undefined }, t);
  }
  assertEquals(parseConfirmationReply("sim 4321 por favor"), { decision: "approve", pin: "4321" });
  // Afirmação pura, que aprovava antes da conferência da sobra, continua aprovando (sem ida ao modelo).
  for (const t of ["sim pode seguir", "sim pode fazer", "sim tá certo", "sim isso mesmo", "ok fechado", "sim é isso", "Sim perfeito"]) {
    assertEquals(parseConfirmationReply(t), { decision: "approve", pin: undefined }, t);
  }
  // O que junta pedido não é cortesia: vai ao modelo.
  for (const t of ["sim e manda", "sim pode mandar tudo", "sim faz também o outro"]) {
    assertEquals(parseConfirmationReply(t), null, t);
  }
});

Deno.test("parseConfirmationReply: PIN com ajuste junto é marcado (o PIN não pode ir ao modelo)", () => {
  assertEquals(parseConfirmationReply("sim 4321 mas manda amanhã"), { decision: "approve", pin: "4321", textoAMais: true });
});

Deno.test("ai-agent: PIN com ajuste junto é tratado antes de resolveWhatsAppConfirmation", () => {
  const src = Deno.readTextFileSync(new URL("../../ai-agent/index.ts", import.meta.url));
  const camada = src.indexOf("const confirmation = parseConfirmationReply(text)");
  const ajuste = src.indexOf("confirmation.textoAMais", camada);
  const resolve = src.indexOf("await resolveWhatsAppConfirmation(", camada);
  assert(ajuste > camada && resolve > ajuste, "textoAMais tem de ser conferido antes de aprovar");
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


// ─── Limite por minuto com o fluxo de comprovantes (decisão 8, 11/10/2026) ───────────────
// Só no modo "dono" e só no telefone do dono foto/PDF não contam (eles vão para o fluxo, e um lote
// de cupons calaria o assistente). Com "off" ou "sombra" (o assistente recebe toda foto), em outro
// telefone, ou com erro ao ler a chave/o dono, a consulta é exatamente a de antes.

const TELEFONE_DO_DONO = "5547999990000";

/** Banco mínimo: devolve o modo e o dono, e registra a cadeia de filtros da contagem. */
function bancoDoLimite(
  modo: { value: string } | null | Error,
  total: number,
  dono: { id: string; phone_normalized: string } | Error = { id: "d1", phone_normalized: TELEFONE_DO_DONO },
) {
  const contagem: Array<[string, ...unknown[]]> = [];
  const admin = {
    from(tabela: string) {
      if (tabela === "app_settings") {
        const q: any = {
          select: () => q,
          eq: () => q,
          maybeSingle: () => modo instanceof Error ? Promise.reject(modo) : Promise.resolve({ data: modo, error: null }),
        };
        return q;
      }
      if (tabela === "app_users") {
        const q: any = {};
        for (const m of ["select", "eq", "not", "order"]) q[m] = () => q;
        q.limit = () => Promise.resolve(dono instanceof Error ? { data: null, error: { message: "db" } } : { data: [dono], error: null });
        return q;
      }
      contagem.push(["from", tabela]);
      const q: any = {};
      for (const m of ["select", "eq", "gte", "in"]) q[m] = (...a: unknown[]) => { contagem.push([m, ...a]); return q; };
      q.then = (ok: (v: unknown) => unknown, falha?: (e: unknown) => unknown) =>
        Promise.resolve({ count: total, error: null }).then(ok, falha);
      return q;
    },
  };
  return { admin, contagem };
}

const FILTROS_DE_ANTES = (desde: unknown, telefone = TELEFONE_DO_DONO) => [
  ["from", "whatsapp_messages"],
  ["select", "*", { count: "exact", head: true }],
  ["eq", "phone_normalized", telefone],
  ["eq", "direction", "inbound"],
  ["gte", "occurred_at", desde],
];

Deno.test("limite por minuto com off ou sombra (ou erro na chave): a consulta de antes, sem filtro de tipo", async () => {
  // sombra: o assistente recebe toda foto (rota ambos) — um lote de 20 fotos segue com o teto de hoje
  for (const modo of [{ value: "off" }, { value: "sombra" }, null, new Error("db"), { value: "lixo" }]) {
    const { admin, contagem } = bancoDoLimite(modo, 3);
    assertEquals(await checkWhatsAppRateLimit(admin, TELEFONE_DO_DONO), true);
    assertEquals(contagem, FILTROS_DE_ANTES(contagem[4]?.[2]));
    assertEquals(contagem.some(([m]) => m === "in"), false);
  }
});

Deno.test("limite por minuto com dono: no telefone do dono só texto e áudio contam", async () => {
  const { admin, contagem } = bancoDoLimite({ value: "dono" }, 3);
  assertEquals(await checkWhatsAppRateLimit(admin, TELEFONE_DO_DONO), true);
  assertEquals(contagem.slice(0, 5), FILTROS_DE_ANTES(contagem[4]?.[2]));
  assertEquals(contagem[5], ["in", "message_type", ["text", "audio"]]);
});

Deno.test("limite por minuto com dono: telefone de funcionário ou dono ilegível conta tudo, como hoje", async () => {
  const funcionario = bancoDoLimite({ value: "dono" }, 3);
  assertEquals(await checkWhatsAppRateLimit(funcionario.admin, "5547988887777"), true);
  assertEquals(funcionario.contagem, FILTROS_DE_ANTES(funcionario.contagem[4]?.[2], "5547988887777"));
  const semDono = bancoDoLimite({ value: "dono" }, 3, new Error("db"));
  assertEquals(await checkWhatsAppRateLimit(semDono.admin, TELEFONE_DO_DONO), true);
  assertEquals(semDono.contagem.some(([m]) => m === "in"), false);
});

Deno.test("limite por minuto: 10 ou mais no minuto bloqueia, nos dois modos", async () => {
  assertEquals(await checkWhatsAppRateLimit(bancoDoLimite({ value: "off" }, 10).admin, TELEFONE_DO_DONO), false);
  assertEquals(await checkWhatsAppRateLimit(bancoDoLimite({ value: "dono" }, 9).admin, TELEFONE_DO_DONO), true);
});

// ─── queueWhatsAppReply devolve o id da mensagem (F2 dos comprovantes, 11/10/2026) ───────
// O registro de pergunta ativa guarda o id do WhatsApp do pedido, para a citação do dono achar
// a pergunta certa. Enviado na hora → o messageId do whatsapp-send; fila ou erro → null.

async function comFetch<T>(resposta: () => Promise<Response>, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = (() => resposta()) as typeof globalThis.fetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = original;
  }
}

function bancoDaFila() {
  const fila: Record<string, unknown>[] = [];
  const admin = {
    from: (_t: string) => ({ insert: (l: Record<string, unknown>) => { fila.push(l); return Promise.resolve({ error: null }); } }),
  };
  return { admin, fila };
}

Deno.test("queueWhatsAppReply: enviado na hora devolve o messageId, sem fila", async () => {
  const { admin, fila } = bancoDaFila();
  const id = await comFetch(
    () => Promise.resolve(new Response(JSON.stringify({ success: true, kind: "text", messageId: "3EB0ABC" }), { status: 200 })),
    () => queueWhatsAppReply(admin, TELEFONE_DO_DONO, "oi"),
  );
  assertEquals(id, "3EB0ABC");
  assertEquals(fila.length, 0);
});

Deno.test("queueWhatsAppReply: enviado sem id do provedor devolve null, sem fila", async () => {
  const { admin, fila } = bancoDaFila();
  const id = await comFetch(
    () => Promise.resolve(new Response(JSON.stringify({ success: true, kind: "text", messageId: null }), { status: 200 })),
    () => queueWhatsAppReply(admin, TELEFONE_DO_DONO, "oi"),
  );
  assertEquals(id, null);
  assertEquals(fila.length, 0);
});

Deno.test("queueWhatsAppReply: erro do envio ou da rede cai na fila e devolve null", async () => {
  for (
    const resposta of [
      () => Promise.resolve(new Response(JSON.stringify({ error: "x" }), { status: 500 })),
      () => Promise.resolve(new Response(JSON.stringify({ error: "x", em_andamento: true }), { status: 409 })),
      () => Promise.reject(new Error("rede")),
    ]
  ) {
    const { admin, fila } = bancoDaFila();
    assertEquals(await comFetch(resposta, () => queueWhatsAppReply(admin, TELEFONE_DO_DONO, "oi")), null);
    assertEquals(fila, [{ phone_normalized: TELEFONE_DO_DONO, message: "oi", source: "ai_agent" }]);
  }
});

// ─── Registro único de pergunta ativa (F2 dos comprovantes, 11/10/2026) ──────────────────
// O dono recebe no mesmo WhatsApp o menu dos comprovantes, a pendência do assistente e o "posso
// mandar?" dos lembretes. Um "sim"/"1" só vai para UM deles. As funções do registro
// (_shared/whatsapp/pergunta-ativa.ts) falam com o banco por rpc: aqui o rpc é dublê, com as
// formas da spec (2.4). Conversa desligada (o padrão) = comportamento de antes, sem leitura nova.

const LIGADA = { comprovante_fluxo: "dono", comprovante_conversa: "on" };
const ABERTA_EM = "2026-10-11T13:00:00.000Z";
const mais = (iso: string, ms: number) => new Date(Date.parse(iso) + ms).toISOString();

/** Banco do registro: rpc com resposta por função, pendências por id, fila de envio; grava a ordem. */
function bancoDoRegistro(rpcs: Record<string, unknown> = {}, pendencias: Record<string, unknown>[] = []) {
  const ordem: string[] = [];
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const fila: Record<string, unknown>[] = [];
  const admin = {
    rpc(fn: string, args: Record<string, unknown>) {
      ordem.push(`rpc:${fn}`);
      chamadas.push({ fn, args });
      const r = rpcs[fn];
      if (r instanceof Error) return Promise.reject(r);
      return Promise.resolve({ data: r ?? null, error: null });
    },
    from(tabela: string) {
      ordem.push(`from:${tabela}`);
      if (tabela === "whatsapp_send_queue") {
        return { insert: (l: Record<string, unknown>) => { fila.push(l); return Promise.resolve({ error: null }); } };
      }
      let linhas = [...pendencias];
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { linhas = linhas.filter((l) => l[c] === v); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
      };
      return q;
    },
  };
  return { admin, ordem, chamadas, fila };
}

/** whatsapp-send dublê: registra a ordem e devolve o messageId. */
async function comEnvio<T>(ordem: string[], messageId: string | null, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = (() => {
    ordem.push("envio");
    return Promise.resolve(new Response(JSON.stringify({ success: true, kind: "text", messageId }), { status: 200 }));
  }) as typeof globalThis.fetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = original;
  }
}

/** O que pergunta_rotear devolve com uma pergunta aberta (de CMP, por padrão) e, se vier, a pendência viva. */
function rotear(p: { pendenciaDesde?: string; citada?: Record<string, unknown> | null; ativa?: "comprovante" | "assistente" | null }) {
  const origem = p.ativa === undefined ? "comprovante" : p.ativa;
  return {
    conversa: true,
    dono: true,
    ativa: origem
      ? {
        id: "perg-1", origem, tipo: origem === "comprovante" ? "pergunta" : "confirmacao", referencia_id: "cmp-1",
        referencia_codigo: "CMP-00124", passo: "para_que", opcoes: [], wa_message_id: "WA-CMP", aberta_em: ABERTA_EM,
      }
      : null,
    citada: p.citada ?? null,
    pendencia: p.pendenciaDesde ? { tipo: "confirmacao", id: "pend-1", titulo: "Lançar no Caixa", desde: p.pendenciaDesde } : null,
    cmp_em_contexto: null,
  };
}

const COM_PENDENCIA = { pending_confirm_action_id: "pend-1" };

Deno.test("conversaDosComprovantesLigada: só fluxo 'dono' E conversa 'on' (aspas, espaços e maiúsculas toleradas)", () => {
  assertEquals(conversaDosComprovantesLigada(LIGADA), true);
  assertEquals(conversaDosComprovantesLigada({ comprovante_fluxo: "\"dono\"", comprovante_conversa: " On " }), true);
  for (
    const s of [
      {}, null, undefined, { comprovante_fluxo: "dono" }, { comprovante_conversa: "on" },
      { comprovante_fluxo: "sombra", comprovante_conversa: "on" }, { comprovante_fluxo: "dono", comprovante_conversa: "off" },
      { comprovante_fluxo: "dono", comprovante_conversa: "sim" },
    ]
  ) assertEquals(conversaDosComprovantesLigada(s as never), false, JSON.stringify(s));
});

Deno.test("trava: 'sim' com a pergunta de CMP mais nova que a pendência NÃO aprova — devolve o desempate", async () => {
  const { admin, chamadas } = bancoDoRegistro({ pergunta_rotear: rotear({ pendenciaDesde: mais(ABERTA_EM, -10 * 60_000) }) });
  const t = await textoDaTravaDoComprovante(admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: null, metadata: COM_PENDENCIA, ligada: true });
  assertStringIncludes(String(t), "CMP-00124");
  assertStringIncludes(String(t), "Lançar no Caixa");
  assertStringIncludes(String(t), "citando a mensagem certa");
  assertEquals(chamadas, [{ fn: "pergunta_rotear", args: { p_phone: TELEFONE_DO_DONO, p_citado: null } }]);
});

Deno.test("trava: '1' com lista do assistente e pergunta de CMP mais nova também trava; empate em < 2 min trava", async () => {
  const opcoes = { pending_options: [{ label: "A", value: "a" }, { label: "B", value: "b" }] };
  const velha = bancoDoRegistro({ pergunta_rotear: rotear({ pendenciaDesde: mais(ABERTA_EM, -30 * 60_000) }) });
  assert(await textoDaTravaDoComprovante(velha.admin, { phone: TELEFONE_DO_DONO, texto: "1", citado: null, metadata: opcoes, ligada: true }));
  const empate = bancoDoRegistro({ pergunta_rotear: rotear({ pendenciaDesde: mais(ABERTA_EM, 119_000) }) });
  assert(await textoDaTravaDoComprovante(empate.admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: null, metadata: COM_PENDENCIA, ligada: true }));
});

Deno.test("trava: pendência mais nova (2 min ou mais), pergunta aberta do assistente ou nenhuma do CMP → aprova como hoje", async () => {
  for (
    const estado of [
      rotear({ pendenciaDesde: mais(ABERTA_EM, 121_000) }),
      rotear({ pendenciaDesde: ABERTA_EM, ativa: "assistente" }),
      rotear({ pendenciaDesde: ABERTA_EM, ativa: null }),
      { conversa: false, dono: true },
    ]
  ) {
    const { admin } = bancoDoRegistro({ pergunta_rotear: estado });
    assertEquals(
      await textoDaTravaDoComprovante(admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: null, metadata: COM_PENDENCIA, ligada: true }),
      null,
      JSON.stringify(estado).slice(0, 80),
    );
  }
});

Deno.test("trava: a citação decide — citou o pedido do assistente (ou fora do registro) segue; citou pergunta de CMP trava", async () => {
  const doAssistente = bancoDoRegistro({
    pergunta_rotear: rotear({
      pendenciaDesde: ABERTA_EM,
      citada: { id: "p2", origem: "assistente", tipo: "confirmacao", referencia_id: "pend-1", status: "aberta", passo: null },
    }),
  });
  assertEquals(
    await textoDaTravaDoComprovante(doAssistente.admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: "WA-PEDIDO", metadata: COM_PENDENCIA, ligada: true }),
    null,
  );
  assertEquals(doAssistente.chamadas[0].args, { p_phone: TELEFONE_DO_DONO, p_citado: "WA-PEDIDO" });
  const fora = bancoDoRegistro({ pergunta_rotear: rotear({ pendenciaDesde: ABERTA_EM }) });
  assertEquals(
    await textoDaTravaDoComprovante(fora.admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: "WA-OUTRA", metadata: COM_PENDENCIA, ligada: true }),
    null,
  );
  const cmpFechada = bancoDoRegistro({
    pergunta_rotear: rotear({
      ativa: null,
      pendenciaDesde: ABERTA_EM,
      citada: { id: "p0", origem: "comprovante", tipo: "pergunta", referencia_id: "cmp-1", status: "respondida", passo: "valor" },
    }),
  });
  assert(await textoDaTravaDoComprovante(cmpFechada.admin, { phone: TELEFONE_DO_DONO, texto: "sim", citado: "WA-CMP", metadata: COM_PENDENCIA, ligada: true }));
});

Deno.test("trava: conversa desligada, sem pendência ou texto que não é confirmação → nenhuma leitura nova", async () => {
  for (
    const p of [
      { texto: "sim", metadata: COM_PENDENCIA, ligada: false },
      { texto: "sim", metadata: {}, ligada: true },
      { texto: "sim", metadata: { pending_confirm_action_id: null, pending_options: [] }, ligada: true },
      { texto: "quantas OS abertas temos?", metadata: COM_PENDENCIA, ligada: true },
    ]
  ) {
    const { admin, ordem } = bancoDoRegistro({ pergunta_rotear: rotear({ pendenciaDesde: ABERTA_EM }) });
    assertEquals(await textoDaTravaDoComprovante(admin, { phone: TELEFONE_DO_DONO, citado: null, ...p }), null);
    assertEquals(ordem, [], JSON.stringify(p));
  }
});

Deno.test("registroDoTurno: proposta nova registra; opções novas registram; texto puro encerra; a mesma de antes não mexe", () => {
  assertEquals(registroDoTurno({}, { pending_confirm_action_id: "pend-9" }, "s1", "Enviar orçamento"), {
    acao: "registrar", tipo: "confirmacao", referencia_id: "pend-9", titulo: "Enviar orçamento",
  });
  const lista = [{ label: "João", value: "c1" }, { label: "Maria", value: "c2" }];
  assertEquals(registroDoTurno({ pending_options: null }, { pending_options: lista, pending_confirm_action_id: null }, "s1", "Qual cliente?"), {
    acao: "registrar", tipo: "opcoes", referencia_id: "s1", titulo: "Qual cliente?",
  });
  assertEquals(registroDoTurno(COM_PENDENCIA, { pending_confirm_action_id: null, pending_options: null }, "s1", null), { acao: "encerrar" });
  assertEquals(registroDoTurno({}, {}, "s1", null), { acao: "encerrar" });
  // A pendência viva que segue esperando (turno de texto no meio dela) e a lista não consumida: nada.
  assertEquals(registroDoTurno(COM_PENDENCIA, { ...COM_PENDENCIA, pendencia_herdada: true }, "s1", null), null);
  assertEquals(registroDoTurno({ pending_options: lista }, { pending_options: lista }, "s1", null), null);
  // A próxima pendência da leva (depois do "sim") registra; sem título, um rótulo genérico.
  assertEquals(registroDoTurno(COM_PENDENCIA, { pending_confirm_action_id: "pend-2" }, "s1", undefined), {
    acao: "registrar", tipo: "confirmacao", referencia_id: "pend-2", titulo: "pedido do assistente",
  });
});

Deno.test("enviarComRegistro: registra ANTES do envio e guarda o id do WhatsApp DEPOIS", async () => {
  const { admin, ordem, chamadas } = bancoDoRegistro({
    pergunta_registrar_externa: { id: "perg-9", substituiu: { origem: "comprovante", referencia_codigo: "CMP-00124" } },
  });
  const wa = await comEnvio(ordem, "WA-9", () =>
    enviarComRegistro(admin, TELEFONE_DO_DONO, "⚠️ Lançar no Caixa", {
      acao: "registrar", tipo: "confirmacao", referencia_id: "pend-9", titulo: "Lançar no Caixa",
    }, { ligada: true }));
  assertEquals(wa, "WA-9");
  assertEquals(ordem, ["rpc:pergunta_registrar_externa", "envio", "rpc:pergunta_marcar_enviada"]);
  assertEquals(chamadas[0].args, {
    p: { phone: TELEFONE_DO_DONO, origem: "assistente", tipo: "confirmacao", referencia_id: "pend-9", titulo: "Lançar no Caixa" },
  });
  assertEquals(chamadas[1].args, { p_id: "perg-9", p_wa_message_id: "WA-9" });
});

Deno.test("enviarComRegistro: origem dos lembretes; encerrar vem depois do envio; desligada = só o envio", async () => {
  const lembrete = bancoDoRegistro({ pergunta_registrar_externa: { id: "perg-L" } });
  await comEnvio(lembrete.ordem, "WA-L", () =>
    enviarComRegistro(lembrete.admin, TELEFONE_DO_DONO, "posso mandar?", {
      acao: "registrar", tipo: "confirmacao", referencia_id: "pend-L", titulo: "Lembrete",
    }, { ligada: true, origem: "campanha_temporada" }));
  assertEquals((lembrete.chamadas[0].args.p as Record<string, unknown>).origem, "campanha_temporada");

  // encerrou alguma pergunta do assistente → a do CMP que ela tinha tirado da vez é retomada
  // (revisão de 11/10/2026); nada encerrado → nada a retomar
  const encerrar = bancoDoRegistro({ pergunta_encerrar_externa: 1 });
  const retomar = (phone: string) => { encerrar.ordem.push(`retomar:${phone}`); return Promise.resolve(); };
  await comEnvio(encerrar.ordem, "WA-E", () => enviarComRegistro(encerrar.admin, TELEFONE_DO_DONO, "ok", { acao: "encerrar" }, { ligada: true, retomar }));
  assertEquals(encerrar.ordem, ["envio", "rpc:pergunta_encerrar_externa", `retomar:${TELEFONE_DO_DONO}`]);
  assertEquals(encerrar.chamadas[0].args, { p_phone: TELEFONE_DO_DONO, p_status: "respondida" });
  const nada = bancoDoRegistro({ pergunta_encerrar_externa: 0 });
  const naoRetoma = () => { nada.ordem.push("retomar"); return Promise.resolve(); };
  await comEnvio(nada.ordem, "WA-N", () => enviarComRegistro(nada.admin, TELEFONE_DO_DONO, "ok", { acao: "encerrar" }, { ligada: true, retomar: naoRetoma }));
  assertEquals(nada.ordem, ["envio", "rpc:pergunta_encerrar_externa"]);
  // retomar que falha não derruba a resposta (o vigia retoma)
  const falha = bancoDoRegistro({ pergunta_encerrar_externa: 2 });
  const wa = await comEnvio(falha.ordem, "WA-X", () =>
    enviarComRegistro(falha.admin, TELEFONE_DO_DONO, "ok", { acao: "encerrar" }, { ligada: true, retomar: () => Promise.reject(new Error("rede")) }));
  assertEquals(wa, "WA-X");

  const registros = [
    { acao: "encerrar" as const },
    { acao: "registrar" as const, tipo: "confirmacao" as const, referencia_id: "x", titulo: "t" },
    null,
  ];
  for (const registro of registros) {
    const desligada = bancoDoRegistro();
    await comEnvio(desligada.ordem, "WA-D", () => enviarComRegistro(desligada.admin, TELEFONE_DO_DONO, "oi", registro, { ligada: false }));
    assertEquals(desligada.ordem, ["envio"], "desligada: nenhuma chamada nova ao banco");
  }
});

Deno.test("enviarComRegistro: registro que falha não impede a mensagem (e nada é marcado sem id)", async () => {
  const { admin, ordem } = bancoDoRegistro({ pergunta_registrar_externa: new Error("rede") });
  const wa = await comEnvio(ordem, "WA-F", () =>
    enviarComRegistro(admin, TELEFONE_DO_DONO, "pedido", { acao: "registrar", tipo: "confirmacao", referencia_id: "p", titulo: "t" }, { ligada: true }));
  assertEquals(wa, "WA-F");
  assertEquals(ordem, ["rpc:pergunta_registrar_externa", "envio"]);
});

Deno.test("donoOcupadoParaPerguntar: ligada pergunta ao registro (pergunta de CMP aberta adia; erro adia)", async () => {
  const cmp = bancoDoRegistro({ pergunta_ocupado: { ocupado: true, por: { origem: "comprovante", titulo: "CMP-00124", desde: ABERTA_EM } } });
  assertEquals(await donoOcupadoParaPerguntar(cmp.admin, { phone: TELEFONE_DO_DONO, metadata: {}, ligada: true }), { ocupado: true, por: "comprovante" });
  assertEquals(cmp.chamadas, [{ fn: "pergunta_ocupado", args: { p_phone: TELEFONE_DO_DONO } }]);
  const livre = bancoDoRegistro({ pergunta_ocupado: { ocupado: false, por: null } });
  assertEquals(await donoOcupadoParaPerguntar(livre.admin, { phone: TELEFONE_DO_DONO, metadata: {}, ligada: true }), { ocupado: false, por: null });
  const erro = bancoDoRegistro({ pergunta_ocupado: new Error("rede") });
  assertEquals(await donoOcupadoParaPerguntar(erro.admin, { phone: TELEFONE_DO_DONO, metadata: {}, ligada: true }), { ocupado: true, por: "erro" });
});

Deno.test("donoOcupadoParaPerguntar: desligada = a checagem de antes (pendência viva da conversa), sem rpc", async () => {
  const viva = bancoDoRegistro({}, [{ id: "pend-1", status: "pending", expires_at: "2999-01-01T00:00:00.000Z", title: "X", risk_level: "medium" }]);
  assertEquals(
    await donoOcupadoParaPerguntar(viva.admin, { phone: TELEFONE_DO_DONO, metadata: COM_PENDENCIA, ligada: false }),
    { ocupado: true, por: "assistente" },
  );
  assertEquals(viva.chamadas.length, 0);
  const nada = bancoDoRegistro();
  assertEquals(await donoOcupadoParaPerguntar(nada.admin, { phone: TELEFONE_DO_DONO, metadata: {}, ligada: false }), { ocupado: false, por: null });
  assertEquals(nada.ordem, [], "sem pendência na conversa: nem lê o banco");
});

// As pontas (index.ts sobe o servidor ao ser importado): conferidas pelo texto da fonte.
const fonte = (rel: string) => Deno.readTextFileSync(new URL(rel, import.meta.url));

Deno.test("ai-agent: a trava vem antes da camada do sim/não; toda resposta de turno passa pelo registro", () => {
  const src = fonte("../../ai-agent/index.ts");
  const trava = src.indexOf("textoDaTravaDoComprovante(admin");
  const camada = src.indexOf("const confirmation = parseConfirmationReply(text)");
  assert(trava > 0 && camada > trava, "a trava tem de vir antes de parseConfirmationReply");
  assertStringIncludes(src, "body.citado");
  assertStringIncludes(src, "body.message_id");
  assertEquals((src.match(/enviarComRegistro\(/g) ?? []).length, 3, "decisão do sim/não, turno do OpenRouter e entrega do Max");
  assertEquals(/queueWhatsAppReply\(admin, phoneNormalized, (replyText|resolved\.message)/.test(src), false, "resposta de turno saindo sem o registro");
});

Deno.test("lembretes-de-revisao e acompanhar-conversas: adiam pelo registro e o lembrete entra nele", () => {
  const lembretes = fonte("../../lembretes-de-revisao/index.ts");
  const acompanhar = fonte("../../acompanhar-conversas/index.ts");
  for (const src of [lembretes, acompanhar]) {
    assertStringIncludes(src, "donoOcupadoParaPerguntar(admin");
    assertStringIncludes(src, "conversaDosComprovantesLigada(settings)");
    assertEquals(src.includes("pendenciaQueSegueEsperando("), false, "a checagem antiga voltou");
  }
  assertStringIncludes(lembretes, "adiado_por_pergunta: true");
  assertStringIncludes(lembretes, "primeira.toque === 0 ? \"campanha_temporada\" : \"lembrete_revisao\"");
  assertEquals(lembretes.includes("queueWhatsAppReply("), false, "o 'posso mandar?' tem de sair pelo registro");
});

// Revisão de 11/10/2026: a pendência que tira a pergunta de um CMP da vez avisa na própria mensagem.
Deno.test("enviarComRegistro: substituiu a pergunta de um CMP → a mensagem diz que ele ficou para depois", async () => {
  assertEquals(avisoDoCmpSubstituido("CMP-00124"), "\n\n(O CMP-00124 ficou para depois: *cmp 124* retoma.)");
  assertEquals(avisoDoCmpSubstituido(null), "");
  const { admin, ordem } = bancoDoRegistro({
    pergunta_registrar_externa: { id: "perg-9", substituiu: { origem: "comprovante", referencia_codigo: "CMP-00124" } },
  });
  const enviados: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((_u: unknown, init?: RequestInit) => {
    ordem.push("envio");
    enviados.push(String(JSON.parse(String(init?.body ?? "{}")).message ?? ""));
    return Promise.resolve(new Response(JSON.stringify({ success: true, kind: "text", messageId: "WA-9" }), { status: 200 }));
  }) as typeof globalThis.fetch;
  try {
    await enviarComRegistro(admin, TELEFONE_DO_DONO, "⚠️ Lançar no Caixa", {
      acao: "registrar", tipo: "confirmacao", referencia_id: "pend-9", titulo: "Lançar no Caixa",
    }, { ligada: true });
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(enviados, ["⚠️ Lançar no Caixa\n\n(O CMP-00124 ficou para depois: *cmp 124* retoma.)"]);
});
