// "Me acorde se" — a coleta (secretário, Passo 4, P4.2, 16/10/2026), com um banco de mentira. O que se protege:
//   · com a voz única desligada NADA é lido (nem a lista de quem espera);
//   · em sombra só o portão é chamado (aviso_registrar) — nenhuma fila, nenhuma pendência, nenhum envio;
//   · o caso Miguel de 07/10: às 09:45 o registro leva o texto com o ORÇ-00113 e a chave da espera; às 14:30 a
//     desistência vai como fato novo (D2: havia orçamento de R$ 5 mil+);
//   · a equipe, o fornecedor e quem já foi respondido não registram;
//   · erro de leitura não derruba a rodada.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { rodadaDeAgora, vigiarAcordes } from "./acordes.ts";
import { PORTAO_DESLIGADO } from "../_shared/uma-voz/registrar.ts";
import { REGRAS_PADRAO } from "../_shared/uma-voz/portao.ts";

const br = (dia: string, hm: string) => new Date(`2026-10-${dia}T${hm}:00-03:00`).toISOString();
const MIGUEL = "351900000422";
const DONO = { id: "u-dono", phone: "5547900009654" };
const SOMBRA = { voz: "sombra" as const, modo: "sombra" as const, regras: { ...REGRAS_PADRAO }, freio: true };

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function banco(tabelas: Record<string, Linha[]>, opcoes: { esperando?: Linha[]; erroNaLista?: boolean } = {}) {
  // deno-lint-ignore no-explicit-any
  const rpcs: Array<{ nome: string; args: any }> = [];
  const lidas: string[] = [];
  const admin = {
    from(t: string) {
      lidas.push(t);
      let linhas = [...(tabelas[t] ?? [])];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => Date.parse(l[c]) >= Date.parse(v))), q),
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (v: unknown) => void) => ok({ data: linhas, error: null }),
      };
      return q;
    },
    // deno-lint-ignore no-explicit-any
    rpc(nome: string, args: any) {
      rpcs.push({ nome, args });
      if (nome === "whatsapp_esperando_resposta") {
        return Promise.resolve(opcoes.erroNaLista ? { data: null, error: { code: "XX000" } } : { data: opcoes.esperando ?? [], error: null });
      }
      if (nome === "aviso_registrar") {
        const p = args.p;
        return Promise.resolve({ data: { ok: true, decisao: p.destino === "acorde" ? "acordar" : "guardar" }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: `rpc inesperada ${nome}` } });
    },
  };
  return { admin, rpcs, lidas };
}

const ESPERANDO_MIGUEL = [{ phone: MIGUEL, contato: "Miguel", categoria: "cliente", encerrada: false, last_inbound_at: br("07", "09:02"), last_outbound_at: br("06", "17:06") }];
const MENSAGENS = [
  { direction: "outbound", phone_normalized: MIGUEL, occurred_at: br("06", "17:06"), body: "🎤 …", client_id: "c-miguel" },
  { direction: "inbound", phone_normalized: MIGUEL, occurred_at: br("07", "09:02"), client_id: "c-miguel",
    body: "🎤 Olá, Gustavo. Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho." },
];
const ORCS = [
  { id: "orc-113", service_order_number: "ORÇ-00113", status: "draft", quote_status: "awaiting_approval", grand_total: 105603.90, client_id: "c-miguel",
    created_at: "2026-10-05T00:45:48Z", updated_at: "2026-10-05T18:46:00Z", quote_validity_days: 3, quote_validity_date: null,
    labor_cost_total: 4720, parts_cost_total: 103514.76, operational_cost_total: 0, travel_cost_total: 0, subcontract_cost_total: 0,
    is_travel_billable: true, discount_amount: 2630.86, tax_amount: 0, custom_payment_installments: null, payment_conditions: null, payment_condition_presets: null },
];

Deno.test("voz única desligada: nada é lido nem registrado", async () => {
  const b = banco({}, { esperando: ESPERANDO_MIGUEL });
  const r = await vigiarAcordes(b.admin, { agora: new Date(br("07", "09:45")), dono: DONO, portao: { ...PORTAO_DESLIGADO, regras: { ...REGRAS_PADRAO } }, settings: {}, internos: new Set(), conversaLigada: true });
  assertEquals(r.disparos, 0);
  assertEquals([b.rpcs.length, b.lidas.length], [0, 0]);
});

Deno.test("Miguel 07/10 09:45 (antes da conferência do dono: 09:45 pede cartão — sem orçamento lido, não pergunta): registra o texto com a proposta", async () => {
  const b = banco({ whatsapp_messages: MENSAGENS, service_orders: ORCS, payment_condition_presets: [], avisos_do_dono: [] }, { esperando: ESPERANDO_MIGUEL });
  const r = await vigiarAcordes(b.admin, {
    agora: new Date(br("07", "09:45")), dono: DONO, portao: SOMBRA, settings: { quote_validity_days: "3", quote_deposit_percentage: "60" },
    internos: new Set([DONO.phone]), conversaLigada: false,
  });
  // 09:45 é depois das 09:30 e há orçamento: a coleta conferiria se o dono está livre (sessão). O banco de mentira
  // não tem a sessão: a conferência falha e fica SEM cartão (na dúvida, só a informação).
  assertEquals([r.conversas, r.disparos, r.acordaria], [1, 1, 1]);
  const reg = b.rpcs.filter((x) => x.nome === "aviso_registrar");
  assertEquals(reg.length, 1);
  const p = reg[0].args.p;
  assertEquals([p.phone, p.modo, p.fonte, p.assunto, p.destino, p.novo_fato], [DONO.phone, "sombra", "cliente", `contato:${MIGUEL}`, "acorde", true]);
  assertEquals(p.chave, `cliente:${MIGUEL}:${br("07", "09:02")}`);
  assertStringIncludes(p.texto, "*Miguel quer fechar hoje.* Áudio às 09:02");
  assertStringIncludes(p.texto, "Proposta pronta: *ORÇ-00113*, R$ 105.603,90 (sinal de R$ 103.301,");
  assertStringIncludes(p.texto, "validade até 07/10");
  assertStringIncludes(p.texto, "Ligue agora: +351900000422");
  assertEquals(p.agora, new Date(br("07", "09:45")).toISOString());
  // nada além do portão: nenhuma fila, nenhuma pendência
  assert(!b.lidas.includes("whatsapp_send_queue") && !b.lidas.includes("ai_operator_pending_actions"));
  assert(b.rpcs.every((x) => ["whatsapp_esperando_resposta", "aviso_registrar"].includes(x.nome)));
});

Deno.test("D11 na coleta: a mesma mensagem que já acordou hoje não é fato novo", async () => {
  const b = banco({
    whatsapp_messages: MENSAGENS, service_orders: [], payment_condition_presets: [],
    avisos_do_dono: [{ phone_normalized: DONO.phone, modo: "sombra", dia: "2026-10-07", assunto: `contato:${MIGUEL}`, situacao: "acordou", dados: { mensagem_em: br("07", "09:02") } }],
  }, { esperando: ESPERANDO_MIGUEL });
  await vigiarAcordes(b.admin, { agora: new Date(br("07", "10:00")), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set(), conversaLigada: false });
  assertEquals(b.rpcs.find((x) => x.nome === "aviso_registrar")!.args.p.novo_fato, false);
});

Deno.test("desistência 14:15 com orçamento de R$ 5 mil+: registra na hora, como fato novo (D2)", async () => {
  const msgs = [...MENSAGENS, { direction: "inbound", phone_normalized: MIGUEL, occurred_at: br("07", "14:15"), client_id: "c-miguel", body: "André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado" }];
  const b = banco({ whatsapp_messages: msgs, service_orders: ORCS, payment_condition_presets: [], avisos_do_dono: [] },
    { esperando: [{ ...ESPERANDO_MIGUEL[0], last_inbound_at: br("07", "14:15") }] });
  await vigiarAcordes(b.admin, { agora: new Date(br("07", "14:16")), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set(), conversaLigada: false });
  const des = b.rpcs.filter((x) => x.nome === "aviso_registrar").map((x) => x.args.p).find((p) => p.chave.startsWith("desistencia:"));
  assert(des, "registrou a desistência");
  assertEquals([des.destino, des.novo_fato], ["acorde", true]);
  assertStringIncludes(des.texto, "*Miguel disse que fechou com outra empresa ou desistiu.*");
  assert(!des.texto.includes("*sim"), "desistência sem cartão");
});

Deno.test("fica de fora: equipe, fornecedor, respondido e quem escreveu ontem; erro na lista não derruba", async () => {
  const esperando = [
    { phone: DONO.phone, contato: "Gustavo", categoria: "cliente", encerrada: false, last_inbound_at: br("07", "09:02") },
    { phone: "5547900004641", contato: "Fornecedor", categoria: "fornecedor", encerrada: false, last_inbound_at: br("07", "09:02") },
    { phone: "5547900001091", contato: "Allana", categoria: "contato", encerrada: false, last_inbound_at: br("06", "11:38") },
  ];
  const b = banco({ whatsapp_messages: [] }, { esperando });
  const r = await vigiarAcordes(b.admin, { agora: new Date(br("07", "10:00")), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set([DONO.phone]), conversaLigada: false });
  assertEquals([r.conversas, r.disparos], [0, 0]);
  assertEquals(b.rpcs.filter((x) => x.nome === "aviso_registrar").length, 0);
  const e = banco({}, { erroNaLista: true });
  const re = await vigiarAcordes(e.admin, { agora: new Date(br("07", "10:00")), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set(), conversaLigada: false });
  assertEquals(re.erro, "XX000");
});

Deno.test("cartão: depois das 09:30, com o dono livre (só LÊ a conversa aberta, não cria sessão), o texto leva o sim/não do PDF", async () => {
  const b = banco({
    whatsapp_messages: MENSAGENS, service_orders: ORCS, payment_condition_presets: [], avisos_do_dono: [],
    ai_operator_sessions: [{ channel: "whatsapp", external_thread_key: DONO.phone, status: "open", metadata: {} }],
  }, { esperando: ESPERANDO_MIGUEL });
  await vigiarAcordes(b.admin, { agora: new Date(br("07", "09:45")), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set(), conversaLigada: false });
  const p = b.rpcs.find((x) => x.nome === "aviso_registrar")!.args.p;
  assertStringIncludes(p.texto, '*sim <seu PIN>* = mando o PDF do ORÇ-00113 com: "Miguel, segue a proposta completa (ORÇ-00113). Se estiver de acordo, confirmo o início com o sinal." · *não* = deixo com você');
  assertEquals(p.dados.cartao, { acao: "send_service_order_link", formato: "pdf", service_order_id: "orc-113", numero: "ORÇ-00113", legenda: "Miguel, segue a proposta completa (ORÇ-00113). Se estiver de acordo, confirmo o início com o sinal." });
  // antes das 09:30 (janela da manhã) o mesmo caso sai sem cartão e nem confere a conversa
  const cedo = banco({ whatsapp_messages: MENSAGENS, service_orders: ORCS, payment_condition_presets: [], avisos_do_dono: [] }, { esperando: ESPERANDO_MIGUEL });
  await vigiarAcordes(cedo.admin, { agora: new Date(br("07", "09:29")), dono: DONO, portao: { ...SOMBRA, regras: { ...REGRAS_PADRAO, acorde_espera_min: 10 } }, settings: {}, internos: new Set(), conversaLigada: false });
  const pc = cedo.rpcs.find((x) => x.nome === "aviso_registrar")!.args.p;
  assert(!pc.texto.includes("*sim"));
  assert(!cedo.lidas.includes("ai_operator_sessions"));
});

// (16/10/2026, decisão do dono) O "me acorde se" vale todos os dias das 08h às 20h; os avisos de acompanhamento e as
// promessas seguem de segunda a sábado.
Deno.test("rodada: domingo só o acorde; sábado os dois; fora das 08–20 nada", () => {
  const em = (iso: string) => rodadaDeAgora(new Date(iso));
  assertEquals(em("2026-10-18T13:00:00Z"), { avisos: false, acordes: true }, "domingo 10:00");
  assertEquals(em("2026-10-18T11:00:00Z"), { avisos: false, acordes: true }, "domingo 08:00");
  assertEquals(em("2026-10-18T22:59:00Z"), { avisos: false, acordes: true }, "domingo 19:59");
  assertEquals(em("2026-10-18T23:00:00Z"), { avisos: false, acordes: false }, "domingo 20:00");
  assertEquals(em("2026-10-18T10:59:00Z"), { avisos: false, acordes: false }, "domingo 07:59");
  assertEquals(em("2026-10-17T13:00:00Z"), { avisos: true, acordes: true }, "sábado 10:00");
  assertEquals(em("2026-10-19T10:59:00Z"), { avisos: false, acordes: false }, "segunda 07:59");
  assertEquals(em("2026-10-19T13:00:00Z"), { avisos: true, acordes: true }, "segunda 10:00");
});

Deno.test("domingo: o detector registra (a coleta não depende do dia da semana)", async () => {
  const b = banco({ whatsapp_messages: [
    { direction: "inbound", phone_normalized: "5547900007900", occurred_at: "2026-10-18T12:28:00Z", client_id: null, body: "Tem disponibilidade hoje pela manhã pra trocar o filtro?" },
  ], service_orders: [], payment_condition_presets: [], avisos_do_dono: [] }, {
    esperando: [{ phone: "5547900007900", contato: "Paulo", categoria: "contato", encerrada: false, last_inbound_at: "2026-10-18T12:28:00Z", last_outbound_at: null }],
  });
  const r = await vigiarAcordes(b.admin, { agora: new Date("2026-10-18T13:00:00Z"), dono: DONO, portao: SOMBRA, settings: {}, internos: new Set(), conversaLigada: false });
  assertEquals([r.disparos, r.acordaria], [1, 1]);
});
