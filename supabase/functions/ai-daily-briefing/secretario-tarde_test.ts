// O turno da tarde inteiro com um banco de mentira (secretário, Passo 3): o que a chave liga, quando espera a
// conversa, o "já decidi hoje", a sombra que nunca envia, o rebaixamento sem a manhã nova e o dry-run.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dentroDoHorario, registrarAgendaDoFechamento, rodarTurnoDaTarde, tentativaDoRelogio } from "./secretario-tarde.ts";

type Linha = Record<string, unknown>;
const DONO = { id: "u-dono", phone: "5547999990000" };
const HOJE = "2026-10-15"; // quinta: fechamento
const AS_1730 = new Date("2026-10-15T20:30:00Z");
const AS_1740 = new Date("2026-10-15T20:40:00Z");
const AS_1750 = new Date("2026-10-15T20:50:00Z");

function valor(l: Linha, c: string): unknown {
  return l[c];
}

/** PostgREST de mentira (filtros sobre linhas em memória) + rpc com respostas e registro das chamadas. */
function falsoAdmin(tabelas: Record<string, Linha[]>, rpcs: Record<string, unknown> = {}) {
  const lidas: string[] = [];
  const chamadas: Array<{ nome: string; args: unknown }> = [];
  const inseridas: Array<{ tabela: string; linhas: unknown }> = [];
  const admin = {
    from(tabela: string) {
      lidas.push(tabela);
      let linhas = [...(tabelas[tabela] ?? [])];
      let soContagem = false;
      const resultado = () => soContagem ? { data: null, error: null, count: linhas.length } : { data: linhas, error: null };
      const q: Record<string, unknown> = {
        select: (_c?: string, o?: { head?: boolean }) => ((soContagem = !!o?.head), q),
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => valor(l, c) === v)), q),
        neq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => valor(l, c) !== v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(valor(l, c)))), q),
        is: (c: string, v: unknown) => ((linhas = linhas.filter((l) => (valor(l, c) ?? null) === v)), q),
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && (valor(l, c) ?? null) === v))), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && String(valor(l, c)) < v)), q),
        lte: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && String(valor(l, c)) <= v)), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && String(valor(l, c)) >= v)), q),
        gt: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && String(valor(l, c)) > v)), q),
        like: () => q,
        or: () => q,
        order: () => q,
        limit: () => q,
        insert: (x: unknown) => (inseridas.push({ tabela, linhas: x }), Promise.resolve({ data: null, error: null })),
        update: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) => Promise.resolve(resultado()).then(ok, erro),
      };
      return q;
    },
    rpc(nome: string, args: unknown) {
      chamadas.push({ nome, args });
      // (20/10/2026) a resposta pode depender do pedido (o guardado da sombra × o do ligado)
      const r = rpcs[nome];
      return Promise.resolve({ data: typeof r === "function" ? (r as (a: unknown) => unknown)(args) : r ?? null, error: null });
    },
  };
  return { admin, lidas, chamadas, inseridas };
}

function banco(p: { formato?: string; modo?: "sombra" | "novo"; comManha?: boolean; tarde?: Linha[]; conversa?: boolean } = {}) {
  return {
    app_settings: [{ key: "fechamento_formato", value: p.formato ?? "sombra" }, { key: "quote_validity_days", value: "3" }],
    app_users: [{ id: DONO.id, phone_normalized: DONO.phone, role: "admin", active: true, ai_whatsapp_enabled: true }],
    resumo_tarde: p.tarde ?? [],
    resumo_manha: p.comManha === false ? [] : [{ id: "m-1", dia: HOJE, phone_normalized: DONO.phone, modo: p.modo ?? "sombra" }],
    resumo_itens: [],
    // o dono escreveu às 17:28, 17:38 e 17:48 (a conversa não para)
    whatsapp_messages: p.conversa
      ? [
        { id: "w1", phone_normalized: DONO.phone, direction: "inbound", occurred_at: "2026-10-15T20:28:00.000Z" },
        { id: "w2", phone_normalized: DONO.phone, direction: "inbound", occurred_at: "2026-10-15T20:38:00.000Z" },
        { id: "w3", phone_normalized: DONO.phone, direction: "inbound", occurred_at: "2026-10-15T20:48:00.000Z" },
      ]
      : [],
    whatsapp_perguntas: [],
    // a conversa do assistente aberta (o histórico entra nela)
    ai_operator_sessions: [{ id: "s-1", channel: "whatsapp", external_thread_key: DONO.phone, status: "open", last_activity_at: new Date().toISOString(), metadata: {} }],
  };
}

// um fornecedor esperando desde 13/10: a tarde tem o que dizer
const RPCS = {
  whatsapp_esperando_resposta: [
    { phone: "5547900000007", contato: "SR Contabilidade", categoria: "fornecedor", last_inbound_at: "2026-10-13T17:02:03Z", last_body: "extrato", encerrada: false },
  ],
  resumo_tarde_registrar: { ok: true, novo: true, enviado: false, calado: false },
};

function registrar(chamadas: Array<{ nome: string; args: unknown }>): Record<string, unknown> | null {
  const c = chamadas.find((x) => x.nome === "resumo_tarde_registrar");
  return c ? (c.args as { p: Record<string, unknown> }).p : null;
}

Deno.test("relógio: tentativas 17:30/17:40/17:50 e a janela 17:25–19:00", () => {
  assertEquals([tentativaDoRelogio(AS_1730), tentativaDoRelogio(AS_1740), tentativaDoRelogio(AS_1750)], [1, 2, 3]);
  assertEquals(tentativaDoRelogio(new Date("2026-10-15T21:30:00Z")), 3);
  assert(dentroDoHorario(AS_1730) && dentroDoHorario(AS_1750));
  assert(!dentroDoHorario(new Date("2026-10-15T13:00:00Z")) && !dentroDoHorario(new Date("2026-10-15T22:00:00Z")));
});

Deno.test("desligado: responde sem ler mais nada além da chave; turno forçado sem dry = 400", async () => {
  const f = falsoAdmin(banco({ formato: "desligado" }), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(r.corpo, { ok: true, motivo: "desligado" });
  assertEquals(f.lidas, ["app_settings"]);
  assertEquals(f.chamadas.length, 0);
  const forcado = await rodarTurnoDaTarde(falsoAdmin(banco()).admin, { agora: AS_1730, pedido: "fechamento", dry: false });
  assertEquals(forcado.status, 400);
  assertEquals((await rodarTurnoDaTarde(falsoAdmin(banco()).admin, { agora: AS_1730, pedido: "manha", dry: true })).status, 400);
});

Deno.test("sombra: grava com enviado=false e formato sombra (nunca envia), com as letras e o escritório", async () => {
  const f = falsoAdmin(banco(), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(r.status, 200);
  const p = registrar(f.chamadas)!;
  assertEquals([p.turno, p.formato, p.modo, p.enviado, p.calado, p.dia, p.phone, p.tentativa], ["fechamento", "sombra", "sombra", false, false, HOJE, DONO.phone, 1]);
  assert(String(p.texto).startsWith("Fechamento de quinta, 15/10: nada ficou de hoje."), String(p.texto));
  assert(String(p.texto).includes("Fornecedores esperando há mais de 1 dia: SR Contabilidade."));
  // (23/10/2026) a carteira foi lida e não tem OS: aí "agenda livre" é verdade
  assert(String(p.texto).includes("Amanhã (sexta, 16/10): agenda livre."), String(p.texto));
  // nada vai para a fila nem para o histórico do assistente
  assertEquals(f.inseridas.length, 0);
});

// ─── (23/10/2026) Aceite da Fase 0 da Agenda de Produção (P4, D11b) ──────────────────────────────
// A carteira ativa de 23/10/2026 como estava no banco (SELECT; ids de mentira): 9 OS, 3 delas esperando o cliente
// (OS-00032/33/76, fora da conta), 5 sem data e a OS-00104 com a janela de 06–08/10, que já passou. Antes, o fechamento
// dizia "agenda livre" com isso tudo parado.
const CARTEIRA_2310: Linha[] = [
  ["OS-00096", "approved", 628.9, "Rodrigo", "MH Overlander - VW Delivery", "2026-10-16T18:57:04Z", null, null],
  ["OS-00032", "awaiting_client", 12500, "KALMAR PERSONAL BOATS", "CAT-33-PAMPLONA", "2026-09-23T12:18:49Z", null, null],
  ["OS-00033", "awaiting_client", 10500, "KALMAR PERSONAL BOATS", "CAT-33-PAMPLONA", "2026-09-29T22:12:54Z", "2026-05-25T08:30:00Z", "2026-05-29T17:00:00Z"],
  ["OS-00076", "awaiting_client", 740, "Rodrigo", "MH Overlander - VW Delivery", "2026-08-08T21:31:38Z", null, null],
  ["OS-00104", "awaiting_parts", 2760, "Flávio da Igreja", "Itapoã", "2026-10-03T23:25:20Z", "2026-10-06T09:00:00Z", "2026-10-08T21:00:00Z"],
  ["OS-00112", "awaiting_parts", 10500, "Nelson", "Santo Inácio 7.8", "2026-10-13T13:10:15Z", null, null],
  ["OS-00069", "open", 9008.99, "Vanderlei Andrade", "Santo Inácio 6.9", "2026-10-03T23:25:20Z", null, null],
  ["OS-00074", "open", 4560, "LENINE LORI BROCCA", "MARCO POLO - VOLVO", "2026-10-13T13:11:38Z", null, null],
  ["OS-00100", "open", 5739, "Giancarlo Ribeiro dos Santos", "Vitória Star", "2026-10-13T13:57:07Z", null, null],
].map(([numero, status, total, cliente, barco, mexido, ini, fim]) => ({
  id: `o-${String(numero).slice(-3)}`, service_order_number: numero, status, grand_total: total, client_id: `c-${String(numero).slice(-3)}`,
  updated_at: mexido, scheduled_start_at: ini, scheduled_end_at: fim, clients: { name: cliente }, vessels: { name: barco, asset_type: "Motorhome" },
}));

Deno.test("aceite (P4): o fechamento de amostra com a carteira real não diz 'agenda livre' — diz quantas OS estão sem data", async () => {
  const b: Record<string, Linha[]> = { ...banco(), service_orders: CARTEIRA_2310 };
  const f = falsoAdmin(b, RPCS);
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const texto = String(registrar(f.chamadas)!.texto);
  assert(!texto.includes("agenda livre"), texto);
  // 9 ativas − 3 esperando o cliente = 6 (a OS-00104, de 06–08/10, tem a data no passado)
  assert(texto.includes("Amanhã (sexta, 16/10): nada marcado; 6 OS ativas sem data (ou com a data vencida)."), texto);
  assert(texto.length <= 1000, `${texto.length}`);
  // a revisão de segunda também
  const seg = falsoAdmin(b, RPCS);
  const r = await rodarTurnoDaTarde(seg.admin, { agora: new Date("2026-10-15T14:00:00Z"), pedido: "revisao_semana", dry: true });
  assert(String(r.corpo.texto).includes("nada marcado; 6 OS ativas sem data (ou com a data vencida)"), String(r.corpo.texto));
});

Deno.test("ligado com a manhã-sombra: rebaixa (grava sem enviar)", async () => {
  const f = falsoAdmin(banco({ formato: "ligado", modo: "sombra" }), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(registrar(f.chamadas)!.enviado, false);
  assertEquals(r.corpo.rebaixado, true);
});

Deno.test("ligado com a manhã nova: espera a conversa às 17:30 e 17:40; às 17:50 envia; sem conversa, envia já", async () => {
  for (const agora of [AS_1730, AS_1740]) {
    const f = falsoAdmin(banco({ formato: "ligado", modo: "novo", conversa: true }), RPCS);
    const r = await rodarTurnoDaTarde(f.admin, { agora, pedido: "tarde", dry: false });
    assertEquals(r.corpo.motivo, "esperando_conversa");
    assertEquals(registrar(f.chamadas), null);
  }
  const ultima = falsoAdmin(banco({ formato: "ligado", modo: "novo", conversa: true }), { ...RPCS, resumo_tarde_registrar: { ok: true, novo: true, enviado: true } });
  await rodarTurnoDaTarde(ultima.admin, { agora: AS_1750, pedido: "tarde", dry: false });
  const p = registrar(ultima.chamadas)!;
  assertEquals([p.enviado, p.formato, p.modo, p.conversa_ativa, p.tentativa], [true, "ligado", "novo", true, 3]);
  assert(Number(p.max_attempts) >= 3);
  // enviado: o texto entra no histórico do assistente com o nome da tarde
  const hist = ultima.inseridas.find((i) => i.tabela === "ai_operator_messages");
  assert(hist && JSON.stringify(hist.linhas).includes("o fechamento das 17:30"));
  const semConversa = falsoAdmin(banco({ formato: "ligado", modo: "novo" }), RPCS);
  await rodarTurnoDaTarde(semConversa.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(registrar(semConversa.chamadas)!.enviado, true);
});

Deno.test("já decidido hoje, sem manhã gravada, fora do horário, sábado: nada é gravado", async () => {
  const ja = falsoAdmin(banco({ tarde: [{ id: "t1", dia: HOJE, phone_normalized: DONO.phone, turno: "fechamento", enviado: false, calado: false }] }), RPCS);
  assertEquals((await rodarTurnoDaTarde(ja.admin, { agora: AS_1740, pedido: "tarde", dry: false })).corpo.motivo, "ja_feito");
  assertEquals(registrar(ja.chamadas), null);
  const semManha = falsoAdmin(banco({ comManha: false }), RPCS);
  assertEquals((await rodarTurnoDaTarde(semManha.admin, { agora: AS_1730, pedido: "tarde", dry: false })).corpo.motivo, "sem_manha");
  assertEquals(registrar(semManha.chamadas), null);
  const cedo = falsoAdmin(banco(), RPCS);
  assertEquals((await rodarTurnoDaTarde(cedo.admin, { agora: new Date("2026-10-15T13:00:00Z"), pedido: "tarde", dry: false })).corpo.motivo, "fora_do_horario");
  const sabado = falsoAdmin(banco(), RPCS);
  assertEquals((await rodarTurnoDaTarde(sabado.admin, { agora: new Date("2026-10-17T20:30:00Z"), pedido: "tarde", dry: false })).corpo.motivo, "sem_tarde_hoje");
});

Deno.test("nada a dizer: grava o dia calado (sem texto), nunca enviado", async () => {
  const f = falsoAdmin(banco({ formato: "ligado", modo: "novo" }), { ...RPCS, whatsapp_esperando_resposta: [] });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const p = registrar(f.chamadas)!;
  assertEquals([p.calado, p.enviado, p.texto], [true, false, null]);
});

Deno.test("dry-run: com a chave desligada, pré-visualiza qualquer turno sem gravar nem enviar", async () => {
  const f = falsoAdmin(banco({ formato: "desligado" }), RPCS);
  const r = await rodarTurnoDaTarde(f.admin, { agora: new Date("2026-10-15T14:00:00Z"), pedido: "revisao_semana", dry: true });
  assertEquals([r.corpo.dry, r.corpo.turno], [true, "revisao_semana"]);
  assert(String(r.corpo.texto).startsWith("Revisão da semana, quinta, 15/10."), String(r.corpo.texto));
  assertEquals(registrar(f.chamadas), null);
  assertEquals(f.inseridas.length, 0);
  assert(!f.lidas.includes("resumo_tarde"), "o dry não consulta o 'já decidi'");
});

// ─── (16/10/2026) O guardado na tarde-sombra, F1 e "com a voz única desligada nada muda" ─────────
// O que se protege: só a tarde que NÃO sai lê o guardado (com a voz única em sombra as fontes já avisaram o dono); o
// texto guardado mostra as linhas; depois de gravar, os mostrados vão para avisos_incluir_na_mensagem SEM fila (a
// migration 20261016120000 os deixa "incluido", nunca "entregue") e o que se resolveu some (aviso_resolver); com a voz
// única desligada ou a tarde enviada, nada disso é lido.
const PROMESSA = '🤖 Lembrete de promessa (detectado numa mensagem sua): você escreveu a Eng. Rafael B. (Dometic) (+55 (47) 90000-0000): "Claro, te passo agora!". Leia a conversa…';
const SALDO = "🏦 Extrato de C6: o saldo do banco (R$ 1.234,56) não bate com a soma das transações importadas (R$ 1.222,26), diferença R$ 12,30. A diferença se repetiu…";
const GUARDADO = {
  ok: true, entregues: 0, voltaram: 0,
  avisos: [
    { id: "g-prom", fonte: "promessa", assunto: "contato:5547900000123", destino: "proxima_fixa", motivo: "destino", texto: PROMESSA, dados: {}, registrado_em: "2026-10-15T12:45:00Z", dia: HOJE, mensagem: "fechamento", reaberto: 0 },
    { id: "g-saldo", fonte: "vigia_negocio", assunto: "saldo_divergente:c6", destino: "escritorio", motivo: "destino", texto: SALDO, dados: { sinal: "saldo_divergente" }, registrado_em: "2026-10-15T09:10:00Z", dia: HOJE, mensagem: "fechamento", reaberto: 0 },
  ],
};

function comVoz(base: Record<string, Linha[]>, voz = "sombra"): Record<string, Linha[]> {
  return { ...base, app_settings: [...base.app_settings, { key: "voz_unica", value: voz }] };
}

Deno.test("guardado na tarde-sombra: 'Não te interrompi com', o escritório na linha dele e a marcação sem fila", async () => {
  const f = falsoAdmin(comVoz(banco()), { ...RPCS, avisos_para_a_mensagem: GUARDADO, avisos_incluir_na_mensagem: { ok: true, incluidos: 2 } });
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const texto = String(registrar(f.chamadas)!.texto);
  assert(texto.includes('Não te interrompi com: promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!".'), texto);
  assert(texto.includes("Escritório: o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença). *escritório*"), texto);
  const incluir = f.chamadas.find((c) => c.nome === "avisos_incluir_na_mensagem");
  const pi = (incluir!.args as { p: Record<string, unknown> }).p;
  assertEquals([pi.modo, pi.ids, "fila_id" in pi], ["sombra", ["g-prom", "g-saldo"], false]);
  assert(f.chamadas.findIndex((c) => c.nome === "resumo_tarde_registrar") < f.chamadas.findIndex((c) => c.nome === "avisos_incluir_na_mensagem"), "marca DEPOIS de gravar");
  assertEquals(r.corpo.guardado_na_sombra, 2);
});

Deno.test("guardado: o contato que já foi respondido some (D8, aviso_resolver) e não aparece", async () => {
  const b = comVoz(banco());
  b.whatsapp_messages = [{ id: "o1", phone_normalized: "5547900000123", direction: "outbound", occurred_at: "2026-10-15T13:00:00.000Z" }];
  const f = falsoAdmin(b, { ...RPCS, avisos_para_a_mensagem: GUARDADO, aviso_resolver: { ok: true, resolvidos: 1 }, avisos_incluir_na_mensagem: { ok: true, incluidos: 1 } });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const texto = String(registrar(f.chamadas)!.texto);
  assert(!texto.includes("Não te interrompi"), texto);
  const res = f.chamadas.find((c) => c.nome === "aviso_resolver");
  assertEquals((res!.args as { p: { ids: string[] } }).p.ids, ["g-prom"]);
});

Deno.test("só o escritório guardado não tira o dia do calado (e não marca nada como mostrado)", async () => {
  const soSaldo = { ...GUARDADO, avisos: [GUARDADO.avisos[1]] };
  const f = falsoAdmin(comVoz(banco()), { ...RPCS, whatsapp_esperando_resposta: [], avisos_para_a_mensagem: soSaldo });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(registrar(f.chamadas)!.calado, true);
  assertEquals(f.chamadas.filter((c) => c.nome === "avisos_incluir_na_mensagem").length, 0);
});

Deno.test("voz única desligada ou tarde enviada: o guardado da sombra nem é lido; o texto é o de antes", async () => {
  const desl = falsoAdmin(banco(), { ...RPCS, avisos_para_a_mensagem: GUARDADO });
  await rodarTurnoDaTarde(desl.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!desl.chamadas.some((c) => c.nome === "avisos_para_a_mensagem"));
  assert(!desl.lidas.includes("avisos_do_dono"));
  // (20/10/2026) a tarde enviada lê o guardado do modo LIGADO (vazio com a voz em sombra), nunca o da sombra
  const soDaSombra = (a: unknown) => ((a as { p: { modo: string } }).p.modo === "sombra" ? GUARDADO : { ok: true, avisos: [] });
  const enviada = falsoAdmin(comVoz(banco({ formato: "ligado", modo: "novo" })), { ...RPCS, avisos_para_a_mensagem: soDaSombra, resumo_tarde_registrar: { ok: true, novo: true, enviado: true } });
  await rodarTurnoDaTarde(enviada.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!enviada.chamadas.some((c) => c.nome === "avisos_para_a_mensagem" && (c.args as { p: { modo: string } }).p.modo === "sombra"),
    "a tarde enviada não repete o que as fontes já avisaram (a sombra)");
  assert(!String(registrar(enviada.chamadas)!.texto).includes("Não te interrompi"));
  assert(!enviada.chamadas.some((c) => c.nome === "avisos_incluir_na_mensagem" || c.nome === "aviso_resolver"), "nada a marcar");
  // o texto da sombra com a voz desligada = o da voz em sombra sem guardado
  const semGuardado = falsoAdmin(comVoz(banco()), { ...RPCS, avisos_para_a_mensagem: { ok: true, avisos: [] } });
  await rodarTurnoDaTarde(semGuardado.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assertEquals(registrar(semGuardado.chamadas)!.texto, registrar(desl.chamadas)!.texto);
});

Deno.test("F1 no fechamento: o cliente que escreveu hoje e está há 4 h sem resposta (e o acordado de hoje)", async () => {
  const b = comVoz(banco());
  b.whatsapp_messages = [
    { phone_normalized: "5547900000555", direction: "inbound", occurred_at: "2026-10-15T13:31:00.000Z", body: "A entrega vc consegue p qdo?" },
    { phone_normalized: "5547900000555", direction: "inbound", occurred_at: "2026-10-15T13:33:00.000Z", body: "quanto vc precisa no pix?" },
    { phone_normalized: "351900000422", direction: "inbound", occurred_at: "2026-10-15T12:02:00.000Z", body: "preciso fechar hoje" },
  ];
  b.avisos_do_dono = [{ phone_normalized: DONO.phone, modo: "sombra", dia: HOJE, situacao: "acordou", assunto: "contato:351900000422", registrado_em: "2026-10-15T12:45:00.000Z" }];
  const esperando = [
    ...RPCS.whatsapp_esperando_resposta,
    { phone: "5547900000555", contato: "Giancarlo S.", categoria: "cliente", last_inbound_at: "2026-10-15T13:33:00Z", last_outbound_at: "2026-10-14T20:00:00Z", encerrada: false },
    { phone: "351900000422", contato: "Miguel", categoria: "cliente", last_inbound_at: "2026-10-15T12:02:00Z", last_outbound_at: null, encerrada: false },
  ];
  const f = falsoAdmin(b, { ...RPCS, whatsapp_esperando_resposta: esperando, avisos_para_a_mensagem: { ok: true, avisos: [] } });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const texto = String(registrar(f.chamadas)!.texto);
  assert(texto.includes("Sem resposta desde hoje: Miguel (09:02, acordei às 09:45); Giancarlo S. (10:31)."), texto);
  // com a voz única desligada, sem o "acordei" (o F1 dos clientes continua: é regra do fechamento)
  const d = falsoAdmin({ ...b, app_settings: banco().app_settings }, { ...RPCS, whatsapp_esperando_resposta: esperando });
  await rodarTurnoDaTarde(d.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(String(registrar(d.chamadas)!.texto).includes("Sem resposta desde hoje: Miguel (09:02); Giancarlo S. (10:31)."), String(registrar(d.chamadas)!.texto));
  // F1 desligado pelo dono (voz_unica_regras.sem_resposta_hoje_horas = 0): a linha some
  const off = falsoAdmin({ ...b, app_settings: [...banco().app_settings, { key: "voz_unica_regras", value: '{"sem_resposta_hoje_horas":0}' }] }, { ...RPCS, whatsapp_esperando_resposta: esperando });
  await rodarTurnoDaTarde(off.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!String(registrar(off.chamadas)!.texto).includes("Sem resposta desde hoje"));
});

// ─── (20/10/2026, P4.5) A tarde ENVIADA com a voz única ligada ────────────────────────────────────
// O que se protege: a tarde que sai lê o guardado do modo LIGADO (as fontes seguraram para ela), mostra "Não te
// interrompi com" e, DEPOIS de gravar e enfileirar (resumo_tarde_registrar), marca os mostrados com o id da linha da
// FILA (achada pela chave secretario_tarde:<dia>:<telefone>, a mesma que a RPC grava). Sem o id: o resolvido some, os
// mostrados NÃO são marcados (voltam na próxima mensagem). O guardado que se resolveu some (aviso_resolver) do mesmo jeito.
Deno.test("P4.5: tarde enviada leva o guardado do ligado e o marca com o id da fila (pela chave da tarde)", async () => {
  const b = comVoz(banco({ formato: "ligado", modo: "novo" }), "ligado");
  b.app_settings = [...b.app_settings, { key: "resumo_formato", value: "novo" }];
  b.whatsapp_send_queue = [{ id: "fila-tarde", dedupe_key: `secretario_tarde:${HOJE}:${DONO.phone}` }];
  const soDoLigado = (a: unknown) => ((a as { p: { modo: string } }).p.modo === "ligado" ? GUARDADO : { ok: true, avisos: [] });
  const f = falsoAdmin(b, {
    ...RPCS, avisos_para_a_mensagem: soDoLigado, resumo_tarde_registrar: { ok: true, novo: true, enviado: true },
    avisos_incluir_na_mensagem: { ok: true, incluidos: 2 },
  });
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const texto = String(registrar(f.chamadas)!.texto);
  assert(texto.includes('Não te interrompi com: promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!".'), texto);
  assert(texto.includes("Escritório: o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença). *escritório*"), texto);
  const leu = f.chamadas.filter((c) => c.nome === "avisos_para_a_mensagem").map((c) => (c.args as { p: { modo: string } }).p.modo);
  assertEquals(leu, ["ligado"]);
  const incluir = f.chamadas.find((c) => c.nome === "avisos_incluir_na_mensagem");
  const pi = (incluir!.args as { p: Record<string, unknown> }).p;
  assertEquals([pi.modo, pi.ids, pi.fila_id], ["ligado", ["g-prom", "g-saldo"], "fila-tarde"]);
  assert(f.chamadas.findIndex((c) => c.nome === "resumo_tarde_registrar") < f.chamadas.findIndex((c) => c.nome === "avisos_incluir_na_mensagem"), "marca DEPOIS de gravar e enfileirar");
  assertEquals(r.corpo.guardado_na_tarde, 2);
  // sem a linha da fila (não achada): nada é incluído — o guardado volta na próxima mensagem
  const sem = falsoAdmin({ ...b, whatsapp_send_queue: [] }, {
    ...RPCS, avisos_para_a_mensagem: soDoLigado, resumo_tarde_registrar: { ok: true, novo: true, enviado: true },
  });
  await rodarTurnoDaTarde(sem.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!sem.chamadas.some((c) => c.nome === "avisos_incluir_na_mensagem"), "ligado sem o id da fila não marca");
  // a 2ª corrida do dia (novo = false) não marca nada
  const segunda = falsoAdmin(b, { ...RPCS, avisos_para_a_mensagem: soDoLigado, resumo_tarde_registrar: { ok: true, novo: false, enviado: true } });
  await rodarTurnoDaTarde(segunda.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!segunda.chamadas.some((c) => c.nome === "avisos_incluir_na_mensagem" || c.nome === "aviso_resolver"));
});

Deno.test("P4.5: tarde rebaixada (a manhã não foi a nova) com a voz ligada não lê nem marca o guardado do ligado", async () => {
  const b = comVoz(banco({ formato: "ligado", modo: "sombra" }), "ligado");
  b.app_settings = [...b.app_settings, { key: "resumo_formato", value: "novo" }];
  const f = falsoAdmin(b, { ...RPCS, avisos_para_a_mensagem: GUARDADO });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!f.chamadas.some((c) => c.nome === "avisos_para_a_mensagem"), "a tarde que não sai não consome o guardado do ligado");
  assert(!String(registrar(f.chamadas)!.texto).includes("Não te interrompi"));
});

// ─── (24/10/2026) Agenda de Produção, Fase 1 (P6): a agenda no fechamento, com o turno inteiro ────────────────────
// A RPC agenda_textos_do_fechamento(p_hoje, p_dia do "Amanhã") devolve o que a agenda diria (os textos do banco de
// verdade, supabase/tests/agenda_fase1_leituras.sql A8/A8b). Em sombra (como nasce) o texto gravado é byte a byte o de
// antes e o que ela diria vai para detalhe.agenda; ligada, ela fala; erro, desligada ou sem a função = a Fase 0.
const CAUDA_DO_BANCO = "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)";
const SEMANA_DO_BANCO = [
  "Semana que vem (projeção): nada marcado; 7 serviços na fila, uns 17 a 32 dias de equipe (~5,4 por semana, sem contar você).",
  "Nenhum pronto para começar; o que falta de você está em *agenda*.",
  "Livre de verdade: no melhor caso a partir de ter 17/11; no realista, só a partir de ter 08/12.",
];
const daAgenda = (modo: string) => ({
  modo, cauda_amanha: CAUDA_DO_BANCO, semana_que_vem: SEMANA_DO_BANCO, dia_do_plano: true, dia: "2026-10-16",
  dados: { prontos: 0, esperando_voce: 7 },
});

async function tardeComAgenda(rpcDaAgenda: unknown | "erro", formato = "sombra") {
  const f = falsoAdmin(banco({ formato }), { ...RPCS, ...(rpcDaAgenda === "erro" ? {} : { agenda_textos_do_fechamento: rpcDaAgenda }) });
  // "erro": a função ainda não existe no banco (42883) — o resto das RPCs responde como sempre
  const admin = rpcDaAgenda === "erro"
    ? {
      from: f.admin.from,
      rpc: (nome: string, args: unknown): Promise<{ data: unknown; error: unknown }> =>
        nome === "agenda_textos_do_fechamento"
          ? (f.chamadas.push({ nome, args }), Promise.resolve({ data: null, error: { code: "42883", message: "function does not exist" } }))
          : f.admin.rpc(nome, args),
    }
    : f.admin;
  await rodarTurnoDaTarde(admin, { agora: AS_1730, pedido: "tarde", dry: false });
  return { p: registrar(f.chamadas)!, chamadas: f.chamadas };
}

Deno.test("agenda em sombra: o fechamento gravado é byte a byte o de antes; o que ela diria vai para detalhe.agenda", async () => {
  const antes = await tardeComAgenda(null);
  const sombra = await tardeComAgenda(daAgenda("sombra"));
  assertEquals(sombra.p.texto, antes.p.texto);
  assertEquals(sombra.p.letras, antes.p.letras);
  assertEquals((sombra.p.detalhe as Record<string, unknown>).agenda, {
    modo: "sombra",
    cauda_diria: `Amanhã (sexta, 16/10): ${CAUDA_DO_BANCO}.`,
    semana_diria: SEMANA_DO_BANCO,
    semana_cabia: true,
    mostrou: false,
  });
  // o resto do detalhe é o de antes (só a chave agenda a mais)
  const { agenda: _a, caracteres: _c1, ...resto } = sombra.p.detalhe as Record<string, unknown>;
  const { caracteres: _c2, ...restoAntes } = antes.p.detalhe as Record<string, unknown>;
  assertEquals(resto, restoAntes);
  // a RPC recebe o dia de hoje e o dia do "Amanhã"
  const c = sombra.chamadas.find((x) => x.nome === "agenda_textos_do_fechamento");
  assertEquals(c?.args, { p_hoje: HOJE, p_dia: "2026-10-16" });
});

Deno.test("agenda ligada: a cauda e, na quinta, a semana que vem saem no texto; o detalhe diz que mostrou", async () => {
  const { p } = await tardeComAgenda(daAgenda("ligado"));
  const linhas = String(p.texto).split("\n");
  const i = linhas.indexOf(`Amanhã (sexta, 16/10): ${CAUDA_DO_BANCO}.`);
  assert(i > 0, String(p.texto));
  assertEquals(linhas.slice(i + 1, i + 4), SEMANA_DO_BANCO);
  assert(String(p.texto).length <= 1000);
  assertEquals((p.detalhe as { agenda: { mostrou: boolean; modo: string } }).agenda.mostrou, true);
  assertEquals((p.detalhe as { agenda: { mostrou: boolean; modo: string } }).agenda.modo, "ligado");
});

Deno.test("agenda com erro, desligada, sem resposta ou sem a função: o fechamento da Fase 0 e nenhum detalhe.agenda", async () => {
  const antes = await tardeComAgenda(null);
  for (const r of ["erro", { modo: "desligado", cauda_amanha: null, semana_que_vem: [], dia_do_plano: false }, { ok: true }, "texto"] as const) {
    const { p } = await tardeComAgenda(r);
    assertEquals(p.texto, antes.p.texto, JSON.stringify(r));
    assert(!("agenda" in (p.detalhe as Record<string, unknown>)), JSON.stringify(r));
  }
});

// (29/10/2026, Agenda de Produção, correção P4) Em 28/10 a leitura da agenda no fechamento estourou o tempo (57014) e o erro
// foi engolido (só console.warn). Agora o fechamento sai igual (sem a agenda) e o erro fica em app_error_logs.
Deno.test("agenda que estoura o tempo (57014): o fechamento sai sem ela e o erro vai para app_error_logs (tarde:agenda)", async () => {
  const antes = await tardeComAgenda(null);
  const f = falsoAdmin(banco({ formato: "sombra" }), RPCS);
  const admin = {
    from: f.admin.from,
    rpc: (nome: string, args: unknown): Promise<{ data: unknown; error: unknown }> =>
      nome === "agenda_textos_do_fechamento"
        ? (f.chamadas.push({ nome, args }),
          Promise.resolve({ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } }))
        : f.admin.rpc(nome, args),
  };
  await rodarTurnoDaTarde(admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const p = registrar(f.chamadas)!;
  assertEquals(p.texto, antes.p.texto);
  assert(!("agenda" in (p.detalhe as Record<string, unknown>)));
  const logs = f.chamadas.filter((c) => c.nome === "log_app_error").map((c) => c.args as Record<string, unknown>);
  assertEquals(logs.length, 1, JSON.stringify(logs));
  assertEquals([logs[0].p_source, logs[0].p_context, logs[0].p_action, logs[0].p_level], ["edge", "ai-daily-briefing", "tarde:agenda", "error"]);
  assertEquals((logs[0].p_details as Record<string, unknown>).codigo, "57014");
  assertEquals(String(logs[0].p_message).startsWith("fechamento: a leitura da agenda (agenda) falhou por tempo esgotado:"), true,
    String(logs[0].p_message));
  // sem erro, nada vai a app_error_logs
  assertEquals(antes.chamadas.some((c) => c.nome === "log_app_error"), false);
});

Deno.test("agenda: só o fechamento e a revisão da semana leem a agenda (o 'Amanhã'); a revisão do mês não", async () => {
  const f = falsoAdmin(banco(), { ...RPCS, agenda_textos_do_fechamento: daAgenda("ligado") });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "revisao_mes", dry: true });
  assert(!f.chamadas.some((c) => c.nome === "agenda_textos_do_fechamento"), "a revisão do mês não tem 'Amanhã'");
  const rs = falsoAdmin(banco(), { ...RPCS, agenda_textos_do_fechamento: daAgenda("ligado") });
  const r = await rodarTurnoDaTarde(rs.admin, { agora: AS_1730, pedido: "revisao_semana", dry: true });
  assert(rs.chamadas.some((c) => c.nome === "agenda_textos_do_fechamento"));
  // na revisão da semana a cauda entra (ligada), a semana que vem não (é do fechamento de quinta)
  assert(String(r.corpo.texto).includes(CAUDA_DO_BANCO), String(r.corpo.texto));
  assert(!String(r.corpo.texto).includes("Semana que vem"), String(r.corpo.texto));
  assertEquals((r.corpo.detalhe as { agenda: { semana_cabia: boolean } }).agenda.semana_cabia, false);
});

// ─── (24/10/2026) Agenda de Produção, Fase 2 (P5): as linhas do plano no fechamento e o registro do que saiu ────────
// O que se protege: o registro (agenda_fechamento_registrar) só depois da tarde gravada E ENVIADA, só com as linhas
// ligadas que saíram no texto; na sombra (formato sombra, rebaixada ou as linhas em sombra) nada é registrado e o que a
// agenda diria vai para detalhe.agenda.linhas_diria. Os textos são os do banco de verdade (agenda_fase2_leituras.sql).
const DECISAO_DO_BANCO = "Agenda, preciso de você. Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa: " +
  "termina ter 17/11 em vez de qui 05/11; 2) Deixo o Nelson fora do plano por enquanto. Recomendo a 1: é o menor atraso (8 dias úteis). Me responda aqui.";
const MUDANCA_DO_BANCO = "Agenda, mudei sozinho. Beatriz (OS-00202): de qui 05/11 para qui 05/11 — quem ia não está mais livre. " +
  "*desfaz Beatriz* volta como estava.";
const comLinhasDoPlano = (modo: "ligado" | "sombra") => ({
  ...daAgenda("ligado"), cauda_amanha: null, semana_que_vem: [],
  linhas: [
    { tipo: "decisao", texto: DECISAO_DO_BANCO, perda: 50, pergunta_id: "q-nelson", acao_ids: [], modo },
    { tipo: "mudancas", texto: MUDANCA_DO_BANCO, perda: 40, pergunta_id: null, acao_ids: ["a-beatriz"], modo },
  ],
});

async function tardeComPlano(agenda: unknown, p: { formato: string; modo: "sombra" | "novo"; enviado: boolean }) {
  const f = falsoAdmin(banco({ formato: p.formato, modo: p.modo }), {
    ...RPCS,
    agenda_textos_do_fechamento: agenda,
    resumo_tarde_registrar: { ok: true, novo: true, enviado: p.enviado, calado: false },
    agenda_fechamento_registrar: { ok: true, perguntas: 1, acoes: 1 },
  });
  const r = await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  return { r, p: registrar(f.chamadas)!, chamadas: f.chamadas };
}

Deno.test("Fase 2: tarde ENVIADA com as linhas do plano — saem depois do 'Amanhã' e o que saiu é registrado (pergunta e ação)", async () => {
  const { r, p, chamadas } = await tardeComPlano(comLinhasDoPlano("ligado"), { formato: "ligado", modo: "novo", enviado: true });
  const linhas = String(p.texto).split("\n");
  const i = linhas.findIndex((l) => l.startsWith("Amanhã (sexta, 16/10)"));
  assertEquals(linhas.slice(i + 1, i + 3), [DECISAO_DO_BANCO, MUDANCA_DO_BANCO]);
  const reg = chamadas.find((c) => c.nome === "agenda_fechamento_registrar");
  assertEquals(reg?.args, {
    p_hoje: HOJE, p_via: "fechamento",
    p_linhas: [{ pergunta_id: "q-nelson", acao_ids: [] }, { pergunta_id: null, acao_ids: ["a-beatriz"] }],
  });
  // o registro vem DEPOIS de gravar e enfileirar a tarde
  assert(chamadas.findIndex((c) => c.nome === "resumo_tarde_registrar") < chamadas.findIndex((c) => c.nome === "agenda_fechamento_registrar"));
  assertEquals(r.corpo.agenda_registrada, { perguntas: 1, acoes: 1 });
  const ag = (p.detalhe as { agenda: Record<string, unknown> }).agenda;
  assertEquals(ag.mostrou, true);
  assertEquals((ag.linhas_mostrou as unknown[]).length, 2);
});

Deno.test("Fase 2: tarde que NÃO sai (sombra ou rebaixada): o texto leva as linhas ligadas, mas nada é registrado", async () => {
  for (const p of [{ formato: "sombra", modo: "sombra" as const, enviado: false }, { formato: "ligado", modo: "sombra" as const, enviado: false }]) {
    const { r, chamadas } = await tardeComPlano(comLinhasDoPlano("ligado"), p);
    assert(!chamadas.some((c) => c.nome === "agenda_fechamento_registrar"), JSON.stringify(p));
    assert(!("agenda_registrada" in r.corpo), JSON.stringify(p));
  }
});

Deno.test("Fase 2: as linhas em sombra: o texto é o de antes byte a byte, o que diria vai ao detalhe, nada é registrado", async () => {
  const antes = await tardeComPlano({ ...daAgenda("ligado"), cauda_amanha: null, semana_que_vem: [] }, { formato: "ligado", modo: "novo", enviado: true });
  const sombra = await tardeComPlano(comLinhasDoPlano("sombra"), { formato: "ligado", modo: "novo", enviado: true });
  assertEquals(sombra.p.texto, antes.p.texto);
  assert(!sombra.chamadas.some((c) => c.nome === "agenda_fechamento_registrar"));
  const ag = (sombra.p.detalhe as { agenda: Record<string, unknown> }).agenda;
  assertEquals(ag.linhas_diria, [
    { tipo: "decisao", perda: 50, modo: "sombra", texto: DECISAO_DO_BANCO },
    { tipo: "mudancas", perda: 40, modo: "sombra", texto: MUDANCA_DO_BANCO },
  ]);
  assertEquals(ag.linhas_mostrou, []);
  assertEquals(ag.mostrou, false);
});

Deno.test("Fase 2: o registro que falha não derruba o fechamento (só o aviso; a linha volta no próximo)", async () => {
  const comErro = {
    rpc: (_n: string, _a: unknown) => Promise.resolve({ data: null, error: { code: "XX000" } }),
  };
  const linhas = [{ tipo: "decisao" as const, texto: DECISAO_DO_BANCO, perda: 50, pergunta_id: "q", acao_ids: [], modo: "ligado" as const }];
  assertEquals(await registrarAgendaDoFechamento(comErro, HOJE, linhas), "erro");
  const lanca = { rpc: () => { throw new Error("rede"); } };
  assertEquals(await registrarAgendaDoFechamento(lanca, HOJE, linhas), "erro");
  const ok = { rpc: () => Promise.resolve({ data: { ok: true, perguntas: 1, acoes: 0 }, error: null }) };
  assertEquals(await registrarAgendaDoFechamento(ok, HOJE, linhas), { perguntas: 1, acoes: 0 });
});

Deno.test("Fase 2: com a agenda automática ligada, o 'Amanhã' pede as OS do plano (agenda_linhas_do_dia) e o estado das OS", async () => {
  const t = { ...banco({ formato: "ligado", modo: "novo" }), agenda_config: [{ id: true, modo_leitura: "ligado", modo_proposta: "ligado", modo_vigia: "ligado" }] };
  const f = falsoAdmin(t, {
    ...RPCS,
    resumo_tarde_registrar: { ok: true, novo: true, enviado: true, calado: false },
    agenda_linhas_do_dia: [{ hora: "08:00", texto: "Vanderlei (OS-00069), dia 1 de 3: você abre…", ord: "2026-10-16T11:00:00+00:00", os: "o-69" }],
    agenda_estado_das_os: [],
  });
  await rodarTurnoDaTarde(f.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  const p = registrar(f.chamadas)!;
  assert(String(p.texto).includes("Amanhã (sexta, 16/10): 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre…."), String(p.texto));
  const pedidos = f.chamadas.filter((c) => c.nome === "agenda_linhas_do_dia").map((c) => c.args);
  // a manhã (hoje, corte 40) e o "Amanhã" (corte 50)
  assertEquals(pedidos, [{ p_dia: HOJE, p_max: 40, p_hoje: HOJE }, { p_dia: "2026-10-16", p_max: 50, p_hoje: HOJE }]);
  assert(f.chamadas.some((c) => c.nome === "agenda_estado_das_os"));
});

// ─── (24/10/2026) Agenda de Produção, Fase 3 (P6): as linhas novas do fechamento ─────────────────────────────────────
// A RPC passa a mandar diaria, conclusao, ppc e comissao (agenda_fase3_acompanhamento.sql). O Secretário as aceita pela
// lista fechada, publica as ligadas nas vagas pela perda e registra o que saiu (a pergunta da diária e a ação da
// conclusão ficam contadas); um tipo que ele não conhece fica de fora (nunca uma linha pela metade).
const DIARIA_DO_BANCO = "Diária, preciso de você: O Roberto respondeu \"fiquei só de manhã\" e o plano de ter 03/11 era o dia todo no " +
  "Vanderlei (OS-00069). 1) meia diária no Vanderlei (OS-00069) (R$ 90,00), como o Roberto disse; 2) dia inteiro no Vanderlei " +
  "(OS-00069) (R$ 180,00), como estava no plano; 3) não lançar. Recomendo a 1: é o que o Roberto respondeu às 17:12. " +
  "*diária Roberto meia* · *diária Roberto inteira* · *diária Roberto não*.";
const CONCLUSAO_DO_BANCO = "Concluí o Vanderlei (OS-00069): o Roberto disse que terminou e era o último dia do plano. As cobranças já " +
  "existiam (sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje. *desfaz OS-00069* reabre.";
const COMISSAO_DO_BANCO = "Comissão de outubro (teste, nada pago): Roberto — diárias R$ 2.400,00 × comissão R$ 0,00; João — diárias " +
  "R$ 1.200,00 × comissão R$ 0,00. *comissão outubro* mostra a conta.";

Deno.test("Fase 3: diária, conclusão e comissão chegam do banco; as que cabem saem e são registradas; tipo desconhecido fica de fora", async () => {
  const agenda = {
    ...daAgenda("ligado"), cauda_amanha: null, semana_que_vem: [],
    linhas: [
      { tipo: "diaria", texto: DIARIA_DO_BANCO, perda: 50, pergunta_id: "q-diaria", acao_ids: [], modo: "ligado" },
      { tipo: "conclusao", texto: CONCLUSAO_DO_BANCO, perda: 45, pergunta_id: null, acao_ids: ["a-concluir"], modo: "ligado" },
      { tipo: "comissao", texto: COMISSAO_DO_BANCO, perda: 20, pergunta_id: null, acao_ids: [], modo: "ligado" },
      { tipo: "inventado", texto: "Uma linha que o Secretário não conhece.", perda: 99, pergunta_id: null, acao_ids: [], modo: "ligado" },
    ],
  };
  const { p, chamadas } = await tardeComPlano(agenda, { formato: "ligado", modo: "novo", enviado: true });
  const linhas = String(p.texto).split("\n");
  const i = linhas.findIndex((l) => l.startsWith("Amanhã (sexta, 16/10)"));
  assertEquals(linhas.slice(i + 1, i + 4), [DIARIA_DO_BANCO, CONCLUSAO_DO_BANCO, COMISSAO_DO_BANCO]);
  assert(!String(p.texto).includes("Secretário não conhece"), "o tipo desconhecido entrou");
  const reg = chamadas.find((c) => c.nome === "agenda_fechamento_registrar");
  assertEquals(reg?.args, {
    p_hoje: HOJE, p_via: "fechamento",
    p_linhas: [{ pergunta_id: "q-diaria", acao_ids: [] }, { pergunta_id: null, acao_ids: ["a-concluir"] }, { pergunta_id: null, acao_ids: [] }],
  });
});

Deno.test("Fase 3: as linhas novas em sombra: o texto é o de antes byte a byte e o que diria vai ao detalhe", async () => {
  const antes = await tardeComPlano({ ...daAgenda("ligado"), cauda_amanha: null, semana_que_vem: [] }, { formato: "ligado", modo: "novo", enviado: true });
  const sombra = await tardeComPlano({
    ...daAgenda("ligado"), cauda_amanha: null, semana_que_vem: [],
    linhas: [
      { tipo: "diaria", texto: DIARIA_DO_BANCO, perda: 50, pergunta_id: "q-diaria", acao_ids: [], modo: "sombra" },
      { tipo: "comissao", texto: COMISSAO_DO_BANCO, perda: 20, pergunta_id: null, acao_ids: [], modo: "sombra" },
    ],
  }, { formato: "ligado", modo: "novo", enviado: true });
  assertEquals(sombra.p.texto, antes.p.texto);
  assert(!sombra.chamadas.some((c) => c.nome === "agenda_fechamento_registrar"));
  const ag = (sombra.p.detalhe as { agenda: Record<string, unknown> }).agenda;
  assertEquals((ag.linhas_diria as Array<{ tipo: string }>).map((l) => l.tipo), ["diaria", "comissao"]);
});
