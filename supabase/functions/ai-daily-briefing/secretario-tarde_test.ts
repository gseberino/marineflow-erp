// O turno da tarde inteiro com um banco de mentira (secretário, Passo 3): o que a chave liga, quando espera a
// conversa, o "já decidi hoje", a sombra que nunca envia, o rebaixamento sem a manhã nova e o dry-run.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dentroDoHorario, rodarTurnoDaTarde, tentativaDoRelogio } from "./secretario-tarde.ts";

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
      return Promise.resolve({ data: rpcs[nome] ?? null, error: null });
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
  // nada vai para a fila nem para o histórico do assistente
  assertEquals(f.inseridas.length, 0);
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

Deno.test("voz única desligada ou tarde enviada: o guardado nem é lido; o texto é o de antes", async () => {
  const desl = falsoAdmin(banco(), { ...RPCS, avisos_para_a_mensagem: GUARDADO });
  await rodarTurnoDaTarde(desl.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!desl.chamadas.some((c) => c.nome === "avisos_para_a_mensagem"));
  assert(!desl.lidas.includes("avisos_do_dono"));
  const enviada = falsoAdmin(comVoz(banco({ formato: "ligado", modo: "novo" })), { ...RPCS, avisos_para_a_mensagem: GUARDADO, resumo_tarde_registrar: { ok: true, novo: true, enviado: true } });
  await rodarTurnoDaTarde(enviada.admin, { agora: AS_1730, pedido: "tarde", dry: false });
  assert(!enviada.chamadas.some((c) => c.nome === "avisos_para_a_mensagem"), "a tarde enviada não repete o que as fontes já avisaram");
  assert(!String(registrar(enviada.chamadas)!.texto).includes("Não te interrompi"));
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
