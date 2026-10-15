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
