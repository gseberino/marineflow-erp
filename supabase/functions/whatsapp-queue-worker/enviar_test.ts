// O envio do lote da fila e a janela da agenda na hora de enviar (Agenda de Produção, Fase 3, P7b — NOVO-agenda-26).
//
// O que estes testes protegem:
//  1. toda origem que não é da agenda sai como sempre, a qualquer hora (domingo à noite incluído), e a configuração da
//     agenda nem é lida — a correção fica restrita à agenda e não mexe no resto do WhatsApp;
//  2. a linha 'agenda-equipe' só sai no dia dela, dentro de [início, fim) de Brasília lido de agenda_config, nunca no
//     domingo e só com a equipe ligada; fora disso vira 'failed' com o motivo, nada é enviado e o registro da mensagem fica
//     recusado pelo mesmo motivo; a leitura que falha não deixa sair (o lado seguro);
//  3. a hora conferida é a de cada envio (a pausa entre um e outro pode passar do fim da janela);
//  4. o index.ts manda só pelo enviarLote.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enviarLote, type ItemDaFila } from "./enviar.ts";
import { origemComJanelaDaAgenda, recusaNaHoraDeEnviar } from "../_shared/agenda/janela-da-fila.ts";

// ── O banco e o provedor de mentira ─────────────────────────────────────────────────────────────────────
interface Escrita {
  tabela: string;
  valores: Record<string, unknown>;
  filtros: Array<[string, unknown]>;
}

function bancoDeMentira(config: { data?: unknown; error?: unknown } = {
  data: { modo_equipe: "ligado", equipe_janela_inicio: "07:30:00", equipe_janela_fim: "20:00:00" },
  error: null,
}) {
  const escritas: Escrita[] = [];
  const leituras: string[] = [];
  const db = {
    from(tabela: string) {
      return {
        select(colunas: string) {
          leituras.push(`${tabela}: ${colunas}`);
          return { maybeSingle: async () => ({ data: config.data ?? null, error: config.error ?? null }) };
        },
        update(valores: Record<string, unknown>) {
          const e: Escrita = { tabela, valores, filtros: [] };
          escritas.push(e);
          const cadeia = {
            eq(col: string, v: unknown) {
              e.filtros.push([col, v]);
              return cadeia;
            },
            then(ok: (r: { error: null }) => unknown) {
              return Promise.resolve({ error: null }).then(ok);
            },
          };
          return cadeia;
        },
      };
    },
  };
  return { db, escritas, leituras };
}

function provedorDeMentira(resposta: (fone: string) => { ok: boolean; providerMessageId?: string; error?: string } = () => ({
  ok: true,
  providerMessageId: "wamid-1",
})) {
  const enviados: string[] = [];
  return {
    enviados,
    provider: {
      sendText: async (fone: string, _texto: string) => {
        enviados.push(fone);
        return resposta(fone);
      },
    },
  };
}

/** Brasília é UTC−3 (sem horário de verão desde 2019). */
const brt = (diaHora: string) => new Date(`${diaHora}-03:00`);
const item = (id: string, source: string | null, marcada: string, extra: Partial<ItemDaFila> = {}): ItemDaFila => ({
  id, phone_normalized: `55479000000${id.padStart(2, "0")}`, message: `mensagem ${id}`, source,
  scheduled_for: brt(marcada).toISOString(), attempts: 0, max_attempts: 3, ...extra,
});
const daFila = (escritas: Escrita[], id: string) =>
  escritas.filter((e) => e.tabela === "whatsapp_send_queue" && e.filtros.some(([c, v]) => c === "id" && v === id));

// ── 1. As outras origens não mudam ──────────────────────────────────────────────────────────────────────
Deno.test("outras origens: saem como sempre, até no domingo às 23:00, e a configuração da agenda nem é lida", async () => {
  const { db, escritas, leituras } = bancoDeMentira({ data: null, error: { message: "não devia ler" } });
  const { provider, enviados } = provedorDeMentira();
  const domingoNoite = brt("2026-11-01T23:00:00");
  const lote = [
    item("1", null, "2026-11-01T22:59:00"),
    item("2", "reply-router", "2026-11-01T03:00:00"),
    item("3", "quote-reminders", "2026-10-30T23:59:00"),
    // a Fase 5 ainda não cadastrou origem de cliente: até lá ela não tem janela (o helper é o único lugar de cadastrar)
    item("4", "agenda-cliente", "2026-11-01T23:00:00"),
    item("5", "Agenda-Equipe", "2026-11-01T23:00:00"),
  ];
  const r = await enviarLote(db, provider, lote, { delayMs: 0, agora: () => domingoNoite });
  assertEquals(enviados.length, 5);
  assertEquals(r.map((x) => x.ok), [true, true, true, true, true]);
  assertEquals(leituras, []);
  for (const x of lote) {
    const w = daFila(escritas, x.id);
    assertEquals(w.length, 1);
    assertEquals(Object.keys(w[0].valores).sort(), ["attempts", "sent_at", "status", "zapi_message_id"]);
    assertEquals([w[0].valores.status, w[0].valores.attempts, w[0].valores.zapi_message_id], ["sent", 1, "wamid-1"]);
  }
  assertEquals(escritas.some((e) => e.tabela !== "whatsapp_send_queue"), false);
});

Deno.test("outras origens: a falha do provedor segue igual (de volta a pending em 5 min; na última tentativa, failed)", async () => {
  const { db, escritas, leituras } = bancoDeMentira();
  const { provider } = provedorDeMentira(() => ({ ok: false, error: "provider fora" }));
  const antes = Date.now();
  const r = await enviarLote(db, provider, [
    item("1", "reply-router", "2026-11-01T23:00:00"),
    item("2", null, "2026-11-01T23:00:00", { attempts: 2, max_attempts: 3 }),
  ], { delayMs: 0, agora: () => brt("2026-11-01T23:00:00") });
  assertEquals(leituras, []);
  assertEquals(r.map((x) => [x.ok, x.give_up, x.error]), [[false, false, "provider fora"], [false, true, "provider fora"]]);
  const [w1] = daFila(escritas, "1");
  assertEquals([w1.valores.status, w1.valores.attempts, w1.valores.failed_reason, w1.valores.processing_started_at],
    ["pending", 1, "provider fora", null]);
  const nova = Date.parse(String(w1.valores.scheduled_for)) - antes;
  assertEquals(nova >= 5 * 60_000 - 50 && nova <= 5 * 60_000 + 5_000, true);
  const [w2] = daFila(escritas, "2");
  assertEquals([w2.valores.status, w2.valores.attempts], ["failed", 3]);
});

Deno.test("outras origens: a exceção do provedor segue igual, e a pausa entre os envios continua", async () => {
  const { db, escritas } = bancoDeMentira();
  const pausas: number[] = [];
  const r = await enviarLote(db, { sendText: async () => { throw new Error("caiu a conexão"); } },
    [item("1", null, "2026-11-03T10:00:00"), item("2", null, "2026-11-03T10:00:00")],
    { delayMs: 1500, agora: () => brt("2026-11-03T10:00:00"), dormir: async (ms) => { pausas.push(ms); } });
  assertEquals(r.map((x) => [x.ok, x.error]), [[false, "caiu a conexão"], [false, "caiu a conexão"]]);
  assertEquals(daFila(escritas, "1")[0].valores.status, "pending");
  assertEquals(pausas, [1500]);
});

// ── 2. A linha da agenda na hora de enviar ──────────────────────────────────────────────────────────────
Deno.test("agenda-equipe dentro da janela, no dia dela e com a equipe ligada: sai (uma leitura da configuração)", async () => {
  const { db, escritas, leituras } = bancoDeMentira();
  const { provider, enviados } = provedorDeMentira();
  const r = await enviarLote(db, provider, [item("1", "agenda-equipe", "2026-11-03T19:30:00")],
    { delayMs: 0, agora: () => brt("2026-11-03T19:31:00") });
  assertEquals(r, [{ id: "1", ok: true }]);
  assertEquals(enviados.length, 1);
  assertEquals(leituras, ["agenda_config: modo_equipe, equipe_janela_inicio, equipe_janela_fim"]);
  assertEquals(daFila(escritas, "1")[0].valores.status, "sent");
});

Deno.test("agenda-equipe às 22:00 (o worker voltou depois do fim): failed com o motivo, nada sai, o registro recusado/janela; a outra origem sai", async () => {
  const { db, escritas } = bancoDeMentira();
  const { provider, enviados } = provedorDeMentira();
  const r = await enviarLote(db, provider, [
    item("1", "agenda-equipe", "2026-11-03T19:30:00", { attempts: 0 }),
    item("2", "reply-router", "2026-11-03T21:59:00"),
  ], { delayMs: 0, agora: () => brt("2026-11-03T22:00:00") });
  assertEquals(enviados, ["5547900000002"]);
  assertEquals(r[0], {
    id: "1", ok: false, give_up: true, janela_da_agenda: "janela",
    error: "agenda-equipe: fora da janela na hora de enviar (07:30–20:00): não saiu",
  });
  assertEquals(r[1], { id: "2", ok: true });
  const [w] = daFila(escritas, "1");
  assertEquals(w.valores, { status: "failed", failed_reason: r[0].error, processing_started_at: null });
  const reg = escritas.filter((e) => e.tabela === "agenda_equipe_mensagens");
  assertEquals(reg.length, 1);
  assertEquals(reg[0].valores, { estado: "recusada", recusa_motivo: "janela" });
  assertEquals(reg[0].filtros, [["fila_id", "1"], ["estado", "enfileirada"]]);
});

Deno.test("agenda-equipe: domingo, o dia de antes, a equipe fora de ligado — cada um com o seu motivo, nada sai", async () => {
  const casos: Array<[string, string, string, unknown, string]> = [
    // [marcada, agora, motivo, modo, trecho do texto]
    ["2026-11-01T10:00:00", "2026-11-01T10:00:00", "domingo", "ligado", "nunca no domingo"],
    ["2026-11-02T19:30:00", "2026-11-03T08:00:00", "janela", "ligado", "era para 02/11 e não saiu no dia dela"],
    ["2026-11-03T08:00:00", "2026-11-03T08:00:00", "modo", "sombra", "modo_equipe saiu de ligado"],
  ];
  for (const [marcada, agora, motivo, modo, trecho] of casos) {
    const { db, escritas } = bancoDeMentira({
      data: { modo_equipe: modo, equipe_janela_inicio: "07:30:00", equipe_janela_fim: "20:00:00" }, error: null,
    });
    const { provider, enviados } = provedorDeMentira();
    const r = await enviarLote(db, provider, [item("1", "agenda-equipe", marcada)], { delayMs: 0, agora: () => brt(agora) });
    assertEquals(enviados, []);
    assertEquals([r[0].ok, r[0].janela_da_agenda], [false, motivo]);
    assertStringIncludes(String(r[0].error), trecho);
    assertEquals(escritas.find((e) => e.tabela === "agenda_equipe_mensagens")?.valores.recusa_motivo, motivo);
  }
});

Deno.test("agenda-equipe: a configuração que não se lê (erro ou horário estranho) não deixa sair, com o erro no motivo", async () => {
  for (const config of [
    { data: null, error: { message: "column agenda_config.equipe_janela_inicio does not exist" } },
    { data: null, error: null },
    { data: { modo_equipe: "ligado", equipe_janela_inicio: "sete e meia", equipe_janela_fim: "20:00:00" }, error: null },
  ]) {
    const { db, escritas } = bancoDeMentira(config);
    const { provider, enviados } = provedorDeMentira();
    const r = await enviarLote(db, provider, [item("1", "agenda-equipe", "2026-11-03T10:00:00")],
      { delayMs: 0, agora: () => brt("2026-11-03T10:00:00") });
    assertEquals(enviados, []);
    assertEquals([r[0].ok, r[0].janela_da_agenda], [false, "janela"]);
    assertStringIncludes(String(r[0].error), "não consegui ler a janela da agenda");
    assertEquals(daFila(escritas, "1")[0].valores.status, "failed");
  }
});

Deno.test("agenda-equipe: a hora é a de cada envio — a pausa leva o 2º para depois do fim e ele não sai; uma leitura só", async () => {
  const { db, leituras } = bancoDeMentira();
  const { provider, enviados } = provedorDeMentira();
  let relogio = brt("2026-11-03T19:59:58").getTime();
  const r = await enviarLote(db, provider, [
    item("1", "agenda-equipe", "2026-11-03T19:30:00"),
    item("2", "agenda-equipe", "2026-11-03T19:30:00"),
    item("3", "reply-router", "2026-11-03T19:30:00"),
  ], {
    delayMs: 1500,
    agora: () => new Date(relogio),
    dormir: async (ms) => { relogio += ms + 1000; },
  });
  assertEquals(r.map((x) => [x.id, x.ok, x.janela_da_agenda ?? null]), [["1", true, null], ["2", false, "janela"], ["3", true, null]]);
  assertEquals(enviados, ["5547900000001", "5547900000003"]);
  assertEquals(leituras.length, 1);
});

Deno.test("a janela: o início fechado e o fim aberto (07:30:00 sai, 20:00:00 não); só 'agenda-equipe' tem janela", () => {
  const j = { equipe: { ligado: true, inicio: "07:30:00", fim: "20:00:00" } };
  const l = (marcada: string, agora: string) => ({ source: "agenda-equipe", scheduled_for: brt(marcada).toISOString(), agora: brt(agora) });
  const a = l("2026-11-03T07:30:00", "2026-11-03T07:30:00");
  assertEquals(recusaNaHoraDeEnviar(a, a.agora, j), null);
  const b = l("2026-11-03T07:29:00", "2026-11-03T07:29:59");
  assertEquals(recusaNaHoraDeEnviar(b, b.agora, j)?.motivo, "janela");
  const c = l("2026-11-03T19:59:00", "2026-11-03T19:59:59");
  assertEquals(recusaNaHoraDeEnviar(c, c.agora, j), null);
  const d = l("2026-11-03T19:59:00", "2026-11-03T20:00:00");
  assertEquals(recusaNaHoraDeEnviar(d, d.agora, j)?.motivo, "janela");
  // sábado é dia da equipe
  const s = l("2026-11-07T08:00:00", "2026-11-07T08:00:00");
  assertEquals(recusaNaHoraDeEnviar(s, s.agora, j), null);
  // os horários são os do banco: com a janela até 21:00, as 20:30 saem
  assertEquals(recusaNaHoraDeEnviar(l("2026-11-03T20:30:00", "2026-11-03T20:30:00"), brt("2026-11-03T20:30:00"),
    { equipe: { ligado: true, inicio: "07:30", fim: "21:00" } }), null);
  for (const o of [null, undefined, "", "reply-router", "quote-reminders", "agenda-cliente", "agenda-equipe ", 7]) {
    assertEquals(origemComJanelaDaAgenda(o), false);
    assertEquals(recusaNaHoraDeEnviar({ source: o, scheduled_for: "x" }, brt("2026-11-01T23:00:00"), null), null);
  }
  assertEquals(origemComJanelaDaAgenda("agenda-equipe"), true);
});

// ── 4. O index.ts manda só pelo enviarLote ──────────────────────────────────────────────────────────────
// (o index.ts sobe o servidor ao ser importado: pelo texto da fonte)
Deno.test("index.ts: o lote vai pelo enviarLote, sem outro sendText", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  assertEquals(fonte.includes('import { enviarLote } from "./enviar.ts";'), true);
  assertEquals(fonte.includes("await enviarLote(admin, provider, batch, { delayMs })"), true);
  assertEquals(fonte.includes("sendText("), false);
});
