// "Me acorde se" com a voz única LIGADA de verdade (secretário, Passo 4, P4.5, 20/10/2026), com um banco de mentira.
// O que se protege:
//   · 'acordar' SAI: sem cartão, pela fila (chave aviso:<id>, prioridade 1) + o par 🤖 no histórico do assistente;
//   · com cartão (orçamento, dono livre, depois das 09:30): a pendência send_service_order_link em PDF nasce do jeito
//     que a tool espera depois do *sim <PIN>* (formato pdf, a legenda, _solicitante admin, o retrato igual ao da tool),
//     a conversa aponta para ela, o par 🤖 vai ao histórico e a mensagem sai com o registro da pergunta;
//   · um cartão por rodada (o 2º acorde vai só com a informação);
//   · 'guardar'/'repetido' não saem; sem resposta do portão o detector não manda nada;
//   · a fila que recusa = reabre o aviso (volta a guardado);
//   · a vendedora sem cadastro nem chega ao portão.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { payloadDoCartao, TITULO_DO_CARTAO, vigiarAcordes } from "./acordes.ts";
import { REGRAS_PADRAO } from "../_shared/uma-voz/portao.ts";
import { legendaDoPdf, lerPendenciaDoEnvio, retratoDoEnvio, validarPedidoDeEnvio } from "../_shared/ai/tools/whatsapp.ts";
import { tituloDaAcao } from "../_shared/ai/agent.ts";

const br = (dia: string, hm: string) => new Date(`2026-10-${dia}T${hm}:00-03:00`).toISOString();
const MIGUEL = "351900000422";
const DONO = { id: "u-dono", phone: "5547900009654" };
const LIGADO = { voz: "ligado" as const, modo: "ligado" as const, regras: { ...REGRAS_PADRAO }, freio: true };

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

// Retorno F5 (P11.5): a validade do envio da proposta pronta. Padrão: a chave desligada (o estado da publicação).
const DESLIGADA = { data: { ok: true, fixou: false, motivo: "desligada" }, error: null };

function banco(tabelas: Record<string, Linha[]>, opcoes: { esperando?: Linha[]; decisao?: Linha | null; erroNaFila?: boolean; validade?: unknown } = {}) {
  // deno-lint-ignore no-explicit-any
  const rpcs: Array<{ nome: string; args: any }> = [];
  const inseridas: Array<{ tabela: string; linhas: unknown }> = [];
  const atualizadas: Array<{ tabela: string; valor: unknown }> = [];
  const admin = {
    from(t: string) {
      let linhas = [...(tabelas[t] ?? [])];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        // (Retorno F0b) .not("saida_humana", "is", false): tira só a saída automática
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && l[c] === v))), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => Date.parse(l[c]) >= Date.parse(v))), q),
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (v: unknown) => void) => ok({ data: linhas, error: null }),
        insert: (x: unknown) => {
          inseridas.push({ tabela: t, linhas: x });
          const erro = t === "whatsapp_send_queue" && opcoes.erroNaFila ? { code: "XX000", message: "fila fora" } : null;
          // deno-lint-ignore no-explicit-any
          const r: any = Promise.resolve({ data: null, error: erro });
          r.select = () => ({ single: () => Promise.resolve({ data: { id: `${t}-1` }, error: null }) });
          return r;
        },
        update: (v: unknown) => (atualizadas.push({ tabela: t, valor: v }), { eq: () => Promise.resolve({ data: null, error: null }) }),
      };
      return q;
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      rpcs.push({ nome, args });
      if (nome === "whatsapp_esperando_resposta") return Promise.resolve({ data: opcoes.esperando ?? [], error: null });
      if (nome === "aviso_registrar") return Promise.resolve(opcoes.decisao === null ? { data: null, error: { message: "permission denied" } } : { data: opcoes.decisao ?? { ok: true, decisao: "acordar", id: "av-1", cartao: false }, error: null });
      if (nome === "aviso_reabrir") return Promise.resolve({ data: { ok: true, resultado: "reaberto" }, error: null });
      if (nome === "orcamento_validade_do_envio") return Promise.resolve(opcoes.validade ?? DESLIGADA);
      return Promise.resolve({ data: null, error: { message: `rpc inesperada ${nome}` } });
    },
  };
  return { admin, rpcs, inseridas, atualizadas };
}

const ESPERANDO_MIGUEL = [{ phone: MIGUEL, contato: "Miguel", categoria: "cliente", encerrada: false, last_inbound_at: br("07", "09:02"), last_outbound_at: br("06", "17:06") }];
const MENSAGENS = [
  { direction: "outbound", phone_normalized: MIGUEL, occurred_at: br("06", "17:06"), body: "🎤 …", client_id: "c-miguel" },
  { direction: "inbound", phone_normalized: MIGUEL, occurred_at: br("07", "09:02"), client_id: "c-miguel",
    body: "🎤 Olá, Gustavo. Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho." },
];
const ORC = {
  id: "orc-113", service_order_number: "ORÇ-00113", status: "draft", quote_status: "awaiting_approval", grand_total: 105603.90, client_id: "c-miguel",
  created_at: "2026-10-05T00:45:48Z", updated_at: "2026-10-05T18:46:00Z", quote_validity_days: 3, quote_validity_date: null,
  labor_cost_total: 4720, parts_cost_total: 103514.76, operational_cost_total: 0, travel_cost_total: 0, subcontract_cost_total: 0,
  is_travel_billable: true, discount_amount: 2630.86, tax_amount: 0, custom_payment_installments: null, payment_conditions: null, payment_condition_presets: null,
  share_token: "tok",
};
const SESSAO = { id: "s-1", channel: "whatsapp", external_thread_key: DONO.phone, status: "open", last_activity_at: "2999-01-01T00:00:00Z", metadata: { x: 1 } };

async function comFetch<T>(fn: () => Promise<T>): Promise<{ r: T; chamadas: string[] }> {
  const original = globalThis.fetch;
  const chamadas: string[] = [];
  globalThis.fetch = ((url: string | URL) => {
    chamadas.push(String(url));
    return Promise.resolve(new Response(JSON.stringify({ messageId: "wa-1" }), { status: 200 }));
  }) as typeof fetch;
  try {
    return { r: await fn(), chamadas };
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test("ligado sem cartão (09:29, janela da manhã): o acorde vai pela fila com a chave aviso:<id> e o par 🤖 no histórico", async () => {
  const b = banco({ whatsapp_messages: MENSAGENS, service_orders: [ORC], payment_condition_presets: [], avisos_do_dono: [], ai_operator_sessions: [SESSAO] },
    { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-1", cartao: false } });
  const r = await vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:29")), dono: DONO, portao: { ...LIGADO, regras: { ...REGRAS_PADRAO, acorde_espera_min: 10 } }, settings: {}, internos: new Set(), conversaLigada: false,
  });
  assertEquals([r.acordaria, r.enviados, r.com_cartao ?? 0], [1, 1, 0]);
  const reg = b.rpcs.find((x) => x.nome === "aviso_registrar")!.args.p;
  assertEquals(reg.modo, "ligado");
  const fila = b.inseridas.filter((x) => x.tabela === "whatsapp_send_queue").map((x) => x.linhas as Linha);
  assertEquals(fila.length, 1);
  assertEquals([fila[0].phone_normalized, fila[0].dedupe_key, fila[0].source, fila[0].priority], [DONO.phone, "aviso:av-1", "me_acorde", 1]);
  assertStringIncludes(fila[0].message, "*Miguel quer fechar hoje.*");
  assert(!fila[0].message.includes("*sim"), "na janela da manhã não há cartão");
  const hist = b.inseridas.find((x) => x.tabela === "ai_operator_messages")!.linhas as Linha[];
  assertEquals(hist.map((m) => [m.session_id, m.role]), [["s-1", "user"], ["s-1", "assistant"]]);
  assert(hist[0].content.startsWith("🤖 Me acorde se"));
  assertEquals(b.inseridas.some((x) => x.tabela === "ai_operator_pending_actions"), false, "sem cartão não há pendência");
});

Deno.test("ligado com cartão (09:45, dono livre): a pendência do PDF como a tool espera, a conversa aponta para ela, a mensagem sai com registro", async () => {
  const b = banco({
    whatsapp_messages: MENSAGENS, service_orders: [ORC], payment_condition_presets: [], avisos_do_dono: [],
    ai_operator_sessions: [SESSAO], clients: [{ id: "c-miguel", name: "Miguel", whatsapp: "+351 900 000 422", phone: null }],
  }, { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-2", cartao: true } });
  const { r, chamadas } = await comFetch(() => vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false,
  }));
  assertEquals([r.enviados, r.com_cartao], [1, 1]);
  const pend = b.inseridas.find((x) => x.tabela === "ai_operator_pending_actions")!.linhas as Linha;
  assertEquals([pend.session_id, pend.requested_by_user_id, pend.action_name, pend.risk_level, pend.status, pend.title],
    ["s-1", DONO.id, "send_service_order_link", "high", "pending", TITULO_DO_CARTAO]);
  assertEquals(pend.payload.service_order_id, "orc-113");
  assertEquals(pend.payload.formato, "pdf");
  assertEquals(pend.payload.custom_message, "Miguel, segue a proposta completa (ORÇ-00113). Se estiver de acordo, confirmo o início com o sinal.");
  assertEquals(pend.payload._solicitante, { user_id: DONO.id, nome: null, cargo: "admin" });
  assertStringIncludes(pend.summary, "Orçamento: *ORÇ-00113* — Total *R$ 105.603,90*");
  assertStringIncludes(pend.summary, "WhatsApp: ••••0422 (do cadastro)");
  // a conversa aponta para a pendência (o *sim <PIN>* do dono cai nela) e guarda o que já tinha
  const sessao = b.atualizadas.find((x) => x.tabela === "ai_operator_sessions")!.valor as Linha;
  assertEquals([sessao.metadata.pending_confirm_action_id, sessao.metadata.pin_attempts, sessao.metadata.pendencia_herdada, sessao.metadata.x],
    ["ai_operator_pending_actions-1", 0, false, 1]);
  // a mensagem sai pelo envio do assistente (com a linha do sim <PIN>), não pela fila do acorde
  assert(chamadas.some((u) => u.endsWith("/functions/v1/whatsapp-send")), JSON.stringify(chamadas));
  assertEquals(b.inseridas.filter((x) => x.tabela === "whatsapp_send_queue").length, 0);
  const hist = b.inseridas.find((x) => x.tabela === "ai_operator_messages")!.linhas as Linha[];
  assertStringIncludes(hist[1].content, "*sim <seu PIN>* = mando o PDF do ORÇ-00113");
  assertStringIncludes(hist[1].content, "(pendência ai_operator_pending_actions-1: send_service_order_link do ORÇ-00113, formato pdf)");
});

Deno.test("a pendência do cartão executa no *sim* como a do assistente: o título, o retrato e a validação da tool", async () => {
  const cartao = { service_order_id: "orc-113", numero: "ORÇ-00113", legenda: "Miguel, segue a proposta completa (ORÇ-00113)." };
  const payload = payloadDoCartao({ cartao, dono: DONO, telefoneDoCadastro: "+351 900 000 422", total: 105603.9 });
  assertEquals(TITULO_DO_CARTAO, tituloDaAcao("send_service_order_link"), "o mesmo título que o assistente daria");
  // o retrato é o MESMO que a tool tira (retratoDoEnvio): o execute compara e não recusa
  const db = {
    from(t: string) {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, eq: () => q,
        maybeSingle: () => Promise.resolve({
          data: t === "service_orders"
            ? { id: "orc-113", service_order_number: "ORÇ-00113", client_id: "c-miguel", status: "draft", grand_total: 105603.9, share_token: "tok" }
            : { whatsapp: "+351 900 000 422", phone: null },
          error: null,
        }),
      };
      return q;
    },
    // Retorno F5 (P11.4): o retrato da tool pergunta a validade do envio; com a chave desligada (o padrão), o retrato de antes
    rpc: () => Promise.resolve({ data: { ok: true, fixou: false, motivo: "desligada" }, error: null }),
  };
  assertEquals(payload._retrato, await retratoDoEnvio(db, { service_order_id: "orc-113" }));
  // lida pela tool, continua PDF (tem _solicitante) e passa na validação com o dono (admin) aprovando
  assertEquals(lerPendenciaDoEnvio(payload).formato, "pdf");
  assertEquals(validarPedidoDeEnvio(lerPendenciaDoEnvio(payload), { userRole: "admin", userId: DONO.id }), null);
});

Deno.test("um cartão por rodada: o 2º acorde (outro cliente) vai só com a informação", async () => {
  const OUTRO = "5547900000555";
  const esperando = [...ESPERANDO_MIGUEL, { phone: OUTRO, contato: "Giancarlo", categoria: "cliente", encerrada: false, last_inbound_at: br("07", "09:05"), last_outbound_at: br("06", "17:00") }];
  const msgs = [...MENSAGENS, { direction: "inbound", phone_normalized: OUTRO, occurred_at: br("07", "09:05"), client_id: "c-gian", body: "Quero fechar hoje o orçamento" }];
  const orc2 = { ...ORC, id: "orc-200", service_order_number: "ORÇ-00200", client_id: "c-gian", grand_total: 9000 };
  let n = 0;
  const b = banco({
    whatsapp_messages: msgs, service_orders: [ORC, orc2], payment_condition_presets: [], avisos_do_dono: [], ai_operator_sessions: [SESSAO],
    clients: [{ id: "c-miguel", name: "Miguel", whatsapp: "+351900000422" }, { id: "c-gian", name: "Giancarlo", whatsapp: "5547900000555" }],
  }, { esperando });
  // o portão libera os dois (com cartão)
  const rpc = b.admin.rpc.bind(b.admin);
  // deno-lint-ignore no-explicit-any
  b.admin.rpc = (nome: string, args: any) => nome === "aviso_registrar"
    ? (b.rpcs.push({ nome, args }), Promise.resolve({ data: { ok: true, decisao: "acordar", id: `av-${++n}`, cartao: true }, error: null }))
    : rpc(nome, args);
  const { r } = await comFetch(() => vigiarAcordes(b.admin, { agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false }));
  assertEquals([r.enviados, r.com_cartao], [2, 1]);
  assertEquals(b.inseridas.filter((x) => x.tabela === "ai_operator_pending_actions").length, 1);
  const fila = b.inseridas.filter((x) => x.tabela === "whatsapp_send_queue").map((x) => x.linhas as Linha);
  assertEquals(fila.length, 1, "o 2º vai pela fila, sem cartão");
  assert(!fila[0].message.includes("*sim"));
});

Deno.test("ligado: guardado, repetido e portão ilegível não saem; a fila que recusa reabre o aviso", async () => {
  for (const decisao of [{ ok: true, decisao: "guardar", id: "g" }, { ok: true, decisao: "repetido", id: "r" }, null]) {
    const b = banco({ whatsapp_messages: MENSAGENS, service_orders: [], payment_condition_presets: [], avisos_do_dono: [], ai_operator_sessions: [SESSAO] },
      { esperando: ESPERANDO_MIGUEL, decisao });
    const r = await vigiarAcordes(b.admin, { agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false });
    assertEquals(r.enviados ?? 0, 0, JSON.stringify(decisao));
    assertEquals(b.inseridas.length, 0, JSON.stringify(decisao));
  }
  const recusa = banco({ whatsapp_messages: MENSAGENS, service_orders: [], payment_condition_presets: [], avisos_do_dono: [], ai_operator_sessions: [SESSAO] },
    { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-9", cartao: false }, erroNaFila: true });
  const r = await vigiarAcordes(recusa.admin, { agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false });
  assertEquals(r.enviados ?? 0, 0);
  assert(recusa.rpcs.some((x) => x.nome === "aviso_reabrir" && x.args.p.id === "av-9"), "volta a guardado");
  assertEquals(recusa.inseridas.some((x) => x.tabela === "ai_operator_messages"), false, "o que não saiu não vai ao histórico");
});

// ═══ Retorno F5 (P11.5; revisão das ondas 4 a 9, achados seguranca-2 e edge-acorde-legenda-sem-validade) ═══════════════
// Com a validade do envio ligada, o banco devolve a O21 e a O22 da prévia (qua 07/10 + 7 = qua 14/10), com o contexto do
// validador (_orcamento_legenda), montado como em _shared/ai/tools/envio-com-validade_test.ts.
const QUARTA = "quarta (14/10)";
const O21 = `Segue o ORÇ-00113, conforme solicitado. Ele vale até ${QUARTA}. Qualquer dúvida, estamos à disposição.`;
const O22 = `Ele vale até ${QUARTA}.`;
const CONTEXTO = {
  audiencia: "cliente", datas_permitidas: [QUARTA], horas_permitidas: [], nome_permitido: null, nomes_de_outros: [],
  os_permitidas: ["ORÇ-00113"], textos_do_cliente: [],
  trechos_do_modelo: ["Segue o ", ", conforme solicitado. Ele vale até ", ". Qualquer dúvida, estamos à disposição.", "Ele vale até ", "."],
  marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false, aceite_registrado: false },
};
const PREVIA = { data: { ok: true, fixou: false, data: "2026-10-14", dias: 7, motivo: "previa", legenda: O21, linha: O22, contexto: CONTEXTO }, error: null };
const TABELAS_DO_CARTAO = () => ({
  whatsapp_messages: MENSAGENS, service_orders: [ORC], payment_condition_presets: [], avisos_do_dono: [],
  ai_operator_sessions: [SESSAO], clients: [{ id: "c-miguel", name: "Miguel", whatsapp: "+351 900 000 422", phone: null }],
});

Deno.test("F5: com a validade do envio ligada, o cartão mostra a O21, a pendência a leva com o retrato da tool, e o *sim* manda o texto que o dono leu", async () => {
  const b = banco(TABELAS_DO_CARTAO(), { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-5", cartao: true }, validade: PREVIA });
  const { r } = await comFetch(() => vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false,
  }));
  assertEquals([r.enviados, r.com_cartao], [1, 1]);
  const pend = b.inseridas.find((x) => x.tabela === "ai_operator_pending_actions")!.linhas as Linha;
  assertEquals(pend.payload.custom_message, O21);
  assertStringIncludes(pend.summary, `Legenda: "${O21}"`);
  const hist = b.inseridas.find((x) => x.tabela === "ai_operator_messages")!.linhas as Linha[];
  assertStringIncludes(hist[1].content, `*sim <seu PIN>* = mando o PDF do ORÇ-00113 com: "${O21}"`);
  assert(!hist[1].content.includes("confirmo o início com o sinal"), hist[1].content);
  // a validade só foi pedida (a prévia, nada gravado)
  const pedidos = b.rpcs.filter((x) => x.nome === "orcamento_validade_do_envio");
  assert(pedidos.length >= 1 && pedidos.every((x) => x.args.p_gravar === false && x.args.p_os === "orc-113"), JSON.stringify(pedidos));
  // o retrato é o MESMO da tool (retratoDoEnvio com a mesma prévia): leva a data, e o *sim* de outro dia cai no 'mudou'
  const db = {
    from(t: string) {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q, eq: () => q,
        maybeSingle: () => Promise.resolve({
          data: t === "service_orders"
            ? { id: "orc-113", service_order_number: "ORÇ-00113", client_id: "c-miguel", status: "draft", grand_total: 105603.9, share_token: "tok", origem: null }
            : { whatsapp: "+351 900 000 422", phone: null },
          error: null,
        }),
      };
      return q;
    },
    rpc: () => Promise.resolve(PREVIA),
  };
  assertEquals(pend.payload._retrato, await retratoDoEnvio(db, { service_order_id: "orc-113" }));
  assertEquals(pend.payload._retrato.validade, "2026-10-14");
  // no *sim* do mesmo dia o envio fixa a mesma data: a legenda que sai é a que o dono leu, byte a byte (sem a O22 a mais)
  const doEnvio = { data: "2026-10-14", motivo: "fixou", legenda: O21, linha: O22 };
  assertEquals(legendaDoPdf(lerPendenciaDoEnvio(pend.payload), { service_order_number: "ORÇ-00113", status: "draft" }, doEnvio), O21);
});

Deno.test("F5: a validade do envio que não deu para prever (erro) — o acorde vai sem cartão, só com a informação", async () => {
  const erro = { data: null, error: { code: "XX000", message: "fora do ar" } };
  const b = banco(TABELAS_DO_CARTAO(), { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-6", cartao: true }, validade: erro });
  const { r } = await comFetch(() => vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false,
  }));
  assertEquals([r.enviados, r.com_cartao ?? 0], [1, 0]);
  assertEquals(b.inseridas.some((x) => x.tabela === "ai_operator_pending_actions"), false, "sem cartão não há pendência");
  const fila = b.inseridas.filter((x) => x.tabela === "whatsapp_send_queue").map((x) => x.linhas as Linha);
  assertEquals(fila.length, 1);
  assert(!fila[0].message.includes("*sim"), fila[0].message);
});

Deno.test("F5: o orçamento do retorno (com origem) segue o ramo da F3 — nem pergunta a validade do envio, e a legenda é a de antes", async () => {
  const tabelas = { ...TABELAS_DO_CARTAO(), service_orders: [{ ...ORC, origem: "retorno_previa" }] };
  const b = banco(tabelas, { esperando: ESPERANDO_MIGUEL, decisao: { ok: true, decisao: "acordar", id: "av-7", cartao: true }, validade: PREVIA });
  await comFetch(() => vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:45")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false,
  }));
  assertEquals(b.rpcs.some((x) => x.nome === "orcamento_validade_do_envio"), false);
  const pend = b.inseridas.find((x) => x.tabela === "ai_operator_pending_actions")!.linhas as Linha;
  assertEquals(pend.payload.custom_message, "Miguel, segue a proposta completa (ORÇ-00113). Se estiver de acordo, confirmo o início com o sinal.");
  assertEquals(pend.payload._retrato.validade, undefined);
});

Deno.test("a vendedora sem cadastro (Ketelyn, 20/10) nem chega ao portão", async () => {
  const k = "5544900009082";
  const b = banco({
    whatsapp_messages: [{ direction: "inbound", phone_normalized: k, occurred_at: br("20", "11:17"), client_id: null,
      body: "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a Tim, esta chegando ao fim. Posso te enviar um orçamento pra voce analisar sem compromisso?" }],
    service_orders: [], payment_condition_presets: [], avisos_do_dono: [],
  }, { esperando: [{ phone: k, contato: "Ketelyn Consultora empresarial", categoria: "contato", encerrada: false, last_inbound_at: br("20", "11:17"), last_outbound_at: null }] });
  const r = await vigiarAcordes(b.admin, { agora: new Date(br("20", "12:00")), dono: DONO, portao: LIGADO, settings: {}, internos: new Set(), conversaLigada: false });
  assertEquals([r.conversas, r.disparos], [1, 0]);
  assertEquals(b.rpcs.filter((x) => x.nome === "aviso_registrar").length, 0);
});
