// O envio do lote da fila e a janela da agenda na hora de enviar (Agenda de Produção, Fase 3, P7b — NOVO-agenda-26).
//
// O que estes testes protegem:
//  1. toda origem que não é da agenda sai como sempre, a qualquer hora (domingo à noite incluído), e a configuração da
//     agenda nem é lida — a correção fica restrita à agenda e não mexe no resto do WhatsApp;
//  2. a linha 'agenda-equipe' só sai no dia dela, dentro de [início, fim) de Brasília lido de agenda_config, nunca no
//     domingo e só com a equipe ligada; fora disso vira 'failed' com o motivo, nada é enviado e o registro da mensagem fica
//     recusado pelo mesmo motivo; a leitura que falha não deixa sair (o lado seguro);
//  3. a hora conferida é a de cada envio (a pausa entre um e outro pode passar do fim da janela);
//  4. o index.ts manda só pelo enviarLote;
//  5. (revisão da Fase 3, C1 — R7, NOVO-agenda-28) a resposta DIRETA à equipe (a chave "agenda-equipe:resposta:…") sai
//     também fora da janela da equipe, dentro da janela dela (06:00–22:00 do banco) e só até o prazo (10 min) depois da
//     mensagem do técnico; nunca no domingo nem com a equipe fora de ligado; a outra linha da agenda segue a janela de sempre;
//  6. (C1, item 10) o lote só leva as linhas que este disparo travou em 'sending' (a outra não sai duas vezes);
//  7. (Fase 4, P5) a linha 'agenda-fornecedor' (a 3ª trava da mensagem ao fornecedor) só sai no dia dela, dentro de
//     [fornecedor_janela_inicio, fornecedor_janela_fim), de segunda a sexta (o sábado só com fornecedor_sabado), com o
//     fornecedor ligado; fora disso vira 'failed' e o registro em agenda_fornecedor_mensagens fica recusado; a janela dele é
//     lida à parte (a que não se lê não segura a equipe); e NENHUMA outra origem muda de comportamento com ela no lote.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enviarLote, type ItemDaFila, travarLote } from "./enviar.ts";
import {
  COLUNAS_DA_JANELA,
  COLUNAS_DA_JANELA_DO_FORNECEDOR,
  ehRespostaDireta,
  intervaloEmSegundos,
  origemComJanelaDaAgenda,
  recusaNaHoraDeEnviar,
} from "../_shared/agenda/janela-da-fila.ts";

/** A linha de agenda_config como o PostgREST devolve (os horários do DEFAULT de 20261026100000). */
const CONFIG = {
  modo_equipe: "ligado", equipe_janela_inicio: "07:30:00", equipe_janela_fim: "20:00:00",
  equipe_resposta_direta_inicio: "06:00:00", equipe_resposta_direta_fim: "22:00:00", equipe_resposta_direta_prazo: "00:10:00",
};

// ── O banco e o provedor de mentira ─────────────────────────────────────────────────────────────────────
interface Escrita {
  tabela: string;
  valores: Record<string, unknown>;
  filtros: Array<[string, unknown]>;
}

function bancoDeMentira(config: { data?: unknown; error?: unknown } = {
  data: CONFIG,
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

/** A janela da resposta direta do DEFAULT (06:00–22:00, 10 min). */
const RD = { inicio: "06:00:00", fim: "22:00:00", prazoSegundos: 600 };

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
  assertEquals(leituras, [`agenda_config: ${COLUNAS_DA_JANELA}`]);
  assertEquals(COLUNAS_DA_JANELA, "modo_equipe, equipe_janela_inicio, equipe_janela_fim, equipe_resposta_direta_inicio, " +
    "equipe_resposta_direta_fim, equipe_resposta_direta_prazo");
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
      data: { ...CONFIG, modo_equipe: modo }, error: null,
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
    { data: { ...CONFIG, equipe_janela_inicio: "sete e meia" }, error: null },
    // (C1) a janela da resposta direta que não se lê também não deixa sair nada da agenda
    { data: { ...CONFIG, equipe_resposta_direta_prazo: "dez minutos" }, error: null },
    { data: { ...CONFIG, equipe_resposta_direta_fim: null }, error: null },
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
  const j = { equipe: { ligado: true, inicio: "07:30:00", fim: "20:00:00" }, respostaDireta: RD };
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
    { equipe: { ligado: true, inicio: "07:30", fim: "21:00" }, respostaDireta: RD }), null);
  for (const o of [null, undefined, "", "reply-router", "quote-reminders", "agenda-cliente", "agenda-equipe ", 7]) {
    assertEquals(origemComJanelaDaAgenda(o), false);
    assertEquals(recusaNaHoraDeEnviar({ source: o, scheduled_for: "x" }, brt("2026-11-01T23:00:00"), null), null);
  }
  assertEquals(origemComJanelaDaAgenda("agenda-equipe"), true);
});

// ── 5. (C1) A resposta direta à equipe ────────────────────────────────────────────────────────────────────
const resposta = (id: string, marcada: string, extra: Partial<ItemDaFila> = {}): ItemDaFila =>
  item(id, "agenda-equipe", marcada, { dedupe_key: `agenda-equipe:resposta:bb000000-0000-4000-8000-000000000002:WA-${id}`, ...extra });

Deno.test("C1 resposta direta: o \"Tá bom\" das 07:10 e das 21:00 sai até 10 min depois; aos 11 min não sai (janela, com o motivo)", async () => {
  const casos: Array<[string, string, boolean]> = [
    ["2026-11-03T07:10:00", "2026-11-03T07:11:00", true],
    ["2026-11-03T07:10:00", "2026-11-03T07:20:00", true],
    ["2026-11-03T07:10:00", "2026-11-03T07:21:00", false],
    ["2026-11-03T21:00:00", "2026-11-03T21:05:00", true],
    ["2026-11-03T21:00:00", "2026-11-03T21:11:00", false],
    ["2026-11-03T21:58:00", "2026-11-03T22:00:00", false], // o fim da janela da resposta é aberto
    ["2026-11-03T05:59:00", "2026-11-03T06:00:00", true], // a hora dela vale (o banco nunca marca antes das 06:00)
    ["2026-11-03T05:50:00", "2026-11-03T05:55:00", false],
    // de manhã, dentro da janela da equipe, é uma linha como as outras (o prazo não corta)
    ["2026-11-03T07:31:00", "2026-11-03T09:00:00", true],
  ];
  for (const [marcada, agora, sai] of casos) {
    const { db, escritas } = bancoDeMentira();
    const { provider, enviados } = provedorDeMentira();
    const r = await enviarLote(db, provider, [resposta("1", marcada)], { delayMs: 0, agora: () => brt(agora) });
    assertEquals([enviados.length === 1, r[0].ok], [sai, sai], `${marcada} → ${agora}`);
    if (!sai) {
      assertEquals(r[0].janela_da_agenda, "janela", `${marcada} → ${agora}`);
      assertEquals(escritas.find((e) => e.tabela === "agenda_equipe_mensagens")?.valores, { estado: "recusada", recusa_motivo: "janela" });
    }
  }
  const { db } = bancoDeMentira();
  const { provider } = provedorDeMentira();
  const r = await enviarLote(db, provider, [resposta("1", "2026-11-03T21:00:00")], { delayMs: 0, agora: () => brt("2026-11-03T21:11:00") });
  assertEquals(r[0].error, "agenda-equipe: a resposta direta só sai até 10 min depois da mensagem dele, de 06:00 a 22:00: não saiu");
});

Deno.test("C1 resposta direta: nunca no domingo, nem com a equipe fora de ligado, nem noutro dia; o prazo conta de quando entrou na fila", async () => {
  const casos: Array<[Partial<ItemDaFila>, string, string, Record<string, unknown>, string]> = [
    [{}, "2026-11-01T10:00:00", "2026-11-01T10:01:00", CONFIG, "domingo"],
    [{}, "2026-11-03T21:00:00", "2026-11-03T21:01:00", { ...CONFIG, modo_equipe: "sombra" }, "modo"],
    [{}, "2026-11-02T21:55:00", "2026-11-03T07:00:00", CONFIG, "janela"],
    // a linha marcada às 21:00 que entrou às 20:45 (a mensagem dele foi às 20:45): às 21:00 já passou o prazo
    [{ created_at: brt("2026-11-03T20:45:00").toISOString() }, "2026-11-03T21:00:00", "2026-11-03T21:00:30", CONFIG, "janela"],
  ];
  for (const [extra, marcada, agora, config, motivo] of casos) {
    const { db } = bancoDeMentira({ data: config, error: null });
    const { provider, enviados } = provedorDeMentira();
    const r = await enviarLote(db, provider, [resposta("1", marcada, extra)], { delayMs: 0, agora: () => brt(agora) });
    assertEquals([enviados.length, r[0].janela_da_agenda], [0, motivo], `${marcada} → ${agora}`);
  }
});

Deno.test("C1 resposta direta: só a chave de resposta da agenda-equipe; a ficha, a confirmação e outra origem às 21:00 não ganham a janela dela", async () => {
  const { db } = bancoDeMentira();
  const { provider, enviados } = provedorDeMentira();
  const as21 = "2026-11-03T21:00:00";
  const r = await enviarLote(db, provider, [
    item("1", "agenda-equipe", as21, { dedupe_key: "agenda-equipe:ficha:bb000000-0000-4000-8000-000000000002:2026-11-04" }),
    item("2", "agenda-equipe", as21, { dedupe_key: "agenda-equipe:confirmar:bb000000-0000-4000-8000-000000000002:2026-11-04" }),
    item("3", "agenda-equipe", as21, { dedupe_key: null }),
    resposta("4", as21),
  ], { delayMs: 0, agora: () => brt("2026-11-03T21:01:00") });
  assertEquals(r.map((x) => [x.id, x.ok]), [["1", false], ["2", false], ["3", false], ["4", true]]);
  assertEquals(enviados, ["5547900000004"]);
  assertEquals(ehRespostaDireta({ source: "agenda-equipe", dedupe_key: "agenda-equipe:resposta:x:y" }), true);
  assertEquals(ehRespostaDireta({ source: "reply-router", dedupe_key: "agenda-equipe:resposta:x:y" }), false);
  assertEquals(ehRespostaDireta({ source: "agenda-equipe", dedupe_key: "agenda-equipe:resposta:x:y:sombra".slice(0, 10) }), false);
  // outra origem com a mesma chave sai como sempre (nem é da agenda)
  assertEquals(recusaNaHoraDeEnviar({ source: "reply-router", scheduled_for: brt(as21).toISOString(), dedupe_key: "agenda-equipe:resposta:x" },
    brt("2026-11-01T23:59:00"), null), null);
});

Deno.test("C1 intervaloEmSegundos: o interval do banco nos três jeitos que o PostgREST devolve; o resto é ilegível", () => {
  assertEquals(intervaloEmSegundos("00:10:00"), 600);
  assertEquals(intervaloEmSegundos("00:10"), 600);
  assertEquals(intervaloEmSegundos("01:00:30"), 3630);
  assertEquals(intervaloEmSegundos("10 minutes"), 600);
  assertEquals(intervaloEmSegundos("10 mins"), 600);
  assertEquals(intervaloEmSegundos("PT10M"), 600);
  assertEquals(intervaloEmSegundos("PT1H30S"), 3630);
  assertEquals(intervaloEmSegundos(600), 600);
  for (const x of ["dez minutos", "", null, undefined, "00:61:00", "PT", -5, "1 day"]) assertEquals(intervaloEmSegundos(x), null, String(x));
});

// ── 6. (C1, item 10) A trava do lote ──────────────────────────────────────────────────────────────────────
function bancoDaTrava(resp: { data: unknown; error: unknown }) {
  const chamadas: Array<[string, unknown]> = [];
  const cadeia = {
    update(v: unknown) { chamadas.push(["update", v]); return cadeia; },
    in(c: string, v: unknown) { chamadas.push([`in ${c}`, v]); return cadeia; },
    eq(c: string, v: unknown) { chamadas.push([`eq ${c}`, v]); return cadeia; },
    select(c: string) { chamadas.push(["select", c]); return Promise.resolve(resp); },
  };
  return { db: { from(t: string) { chamadas.push(["from", t]); return cadeia; } }, chamadas };
}

Deno.test("C1 travarLote: só as linhas que o UPDATE devolveu vão ao envio (a que outro disparo pegou não sai duas vezes)", async () => {
  const lote = [item("1", "agenda-equipe", "2026-11-03T19:30:00"), item("2", null, "2026-11-03T19:30:00"), item("3", null, "2026-11-03T19:30:00")];
  const { db, chamadas } = bancoDaTrava({ data: [{ id: "1" }, { id: "3" }], error: null });
  const r = await travarLote(db, lote, "2026-11-03T22:30:00.000Z");
  assertEquals(r.lote.map((x) => x.id), ["1", "3"]);
  assertEquals(r.erro, undefined);
  assertEquals(chamadas, [
    ["from", "whatsapp_send_queue"],
    ["update", { status: "sending", processing_started_at: "2026-11-03T22:30:00.000Z" }],
    ["in id", ["1", "2", "3"]],
    ["eq status", "pending"],
    ["select", "id"],
  ]);
  // nenhuma travada (outro disparo levou todas): nada vai ao envio
  assertEquals((await travarLote(bancoDaTrava({ data: [], error: null }).db, lote, "x")).lote, []);
  assertEquals((await travarLote(bancoDaTrava({ data: null, error: null }).db, lote, "x")).lote, []);
  // erro na trava: nada sai (seguem pendentes para o próximo minuto)
  const e = await travarLote(bancoDaTrava({ data: null, error: { message: "timeout" } }).db, lote, "x");
  assertEquals([e.lote, e.erro], [[], "timeout"]);
  // lote vazio nem chama o banco
  const v = bancoDaTrava({ data: [], error: null });
  assertEquals((await travarLote(v.db, [], "x")).lote, []);
  assertEquals(v.chamadas, []);
});

// ── 4. O index.ts manda só pelo enviarLote ──────────────────────────────────────────────────────────────
// (o index.ts sobe o servidor ao ser importado: pelo texto da fonte)
Deno.test("index.ts: o lote vai pelo enviarLote, sem outro sendText", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  assertEquals(fonte.includes('import { enviarLote, travarLote } from "./enviar.ts";'), true);
  // (C1, item 10) a trava conferida: o lote do envio é o que travarLote devolveu, nunca o batch lido
  const trava = fonte.indexOf("await travarLote(admin, batch, nowIso)");
  const envio = fonte.indexOf("await enviarLote(admin, provider, lote, { delayMs })");
  assertEquals(trava > 0 && envio > trava, true);
  assertEquals(fonte.includes("enviarLote(admin, provider, batch"), false);
  assertEquals(fonte.includes('.update({ status: "sending"'), false);
  assertEquals(fonte.includes("sendText("), false);
});

// ── 7. (Fase 4, P5) A mensagem ao fornecedor: a 3ª trava ────────────────────────────────────────────────
/** A linha de agenda_config por colunas pedidas (cada janela é um SELECT à parte). */
const CONFIG_FORNECEDOR = {
  modo_fornecedor: "ligado", fornecedor_janela_inicio: "08:00:00", fornecedor_janela_fim: "18:00:00", fornecedor_sabado: false,
};
function bancoPorColunas(respostas: Record<string, { data?: unknown; error?: unknown }> = {
  [COLUNAS_DA_JANELA]: { data: CONFIG },
  [COLUNAS_DA_JANELA_DO_FORNECEDOR]: { data: CONFIG_FORNECEDOR },
}) {
  const escritas: Escrita[] = [];
  const leituras: string[] = [];
  const db = {
    from(tabela: string) {
      return {
        select(colunas: string) {
          leituras.push(`${tabela}: ${colunas}`);
          const r = respostas[colunas] ?? { data: null, error: { message: `coluna não esperada: ${colunas}` } };
          return { maybeSingle: async () => ({ data: r.data ?? null, error: r.error ?? null }) };
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
const forn = (id: string, marcada: string, extra: Partial<ItemDaFila> = {}) =>
  item(id, "agenda-fornecedor", marcada, { dedupe_key: `agenda-fornecedor:terco:linha-${id}:2`, ...extra });

Deno.test("P5 agenda-fornecedor na janela (qua 10:00) com o fornecedor ligado: sai; só a configuração do fornecedor é lida, uma vez", async () => {
  const { db, escritas, leituras } = bancoPorColunas();
  const { provider, enviados } = provedorDeMentira();
  const r = await enviarLote(db, provider, [forn("1", "2026-10-28T10:00:00"), forn("2", "2026-10-28T10:00:00")],
    { delayMs: 0, agora: () => brt("2026-10-28T10:01:00") });
  assertEquals(r, [{ id: "1", ok: true }, { id: "2", ok: true }]);
  assertEquals(enviados.length, 2);
  assertEquals(leituras, [`agenda_config: ${COLUNAS_DA_JANELA_DO_FORNECEDOR}`]);
  assertEquals(daFila(escritas, "1")[0].valores.status, "sent");
});

Deno.test("P5 agenda-fornecedor às 19:00 (o worker voltou depois do fim): failed com o motivo, nada sai, o registro do fornecedor recusado/janela; a outra origem sai", async () => {
  const { db, escritas } = bancoPorColunas();
  const { provider, enviados } = provedorDeMentira();
  const r = await enviarLote(db, provider, [
    forn("1", "2026-10-28T10:00:00"),
    item("2", "reply-router", "2026-10-28T18:59:00"),
  ], { delayMs: 0, agora: () => brt("2026-10-28T19:00:00") });
  assertEquals(enviados, ["5547900000002"]);
  assertEquals(r[0], {
    id: "1", ok: false, give_up: true, janela_da_agenda: "janela",
    error: "agenda-fornecedor: fora da janela na hora de enviar (08:00–18:00): não saiu",
  });
  assertEquals(daFila(escritas, "1")[0].valores, { status: "failed", failed_reason: r[0].error, processing_started_at: null });
  const reg = escritas.filter((e) => e.tabela === "agenda_fornecedor_mensagens");
  assertEquals(reg.length, 1);
  assertEquals(reg[0].valores, { estado: "recusada", recusa_motivo: "janela" });
  assertEquals(reg[0].filtros, [["fila_id", "1"], ["estado", "enfileirada"]]);
  assertEquals(escritas.some((e) => e.tabela === "agenda_equipe_mensagens"), false);
});

Deno.test("P5 agenda-fornecedor: sábado (fim_de_semana), domingo, o fornecedor fora de ligado — cada um com o seu motivo; com fornecedor_sabado o sábado sai", async () => {
  const casos: Array<[string, string, Record<string, unknown>, string | null]> = [
    ["2026-10-31T10:00:00", "2026-10-31T10:00:00", CONFIG_FORNECEDOR, "fim_de_semana"],
    ["2026-11-01T10:00:00", "2026-11-01T10:00:00", { ...CONFIG_FORNECEDOR, fornecedor_sabado: true }, "domingo"],
    ["2026-10-28T10:00:00", "2026-10-28T10:00:00", { ...CONFIG_FORNECEDOR, modo_fornecedor: "sombra" }, "modo"],
    ["2026-10-31T10:00:00", "2026-10-31T10:00:00", { ...CONFIG_FORNECEDOR, fornecedor_sabado: true }, null],
  ];
  for (const [marcada, agora, config, motivo] of casos) {
    const { db, escritas } = bancoPorColunas({ [COLUNAS_DA_JANELA_DO_FORNECEDOR]: { data: config } });
    const { provider, enviados } = provedorDeMentira();
    const r = await enviarLote(db, provider, [forn("1", marcada)], { delayMs: 0, agora: () => brt(agora) });
    assertEquals([enviados.length, r[0].janela_da_agenda ?? null], [motivo ? 0 : 1, motivo], `${marcada} ${JSON.stringify(config)}`);
    if (motivo) {
      assertEquals(escritas.find((e) => e.tabela === "agenda_fornecedor_mensagens")?.valores.recusa_motivo, motivo);
    }
  }
});

Deno.test("P5 a janela do fornecedor que não se lê (a migration da Fase 4 ainda não aplicada) não segura a equipe nem as outras origens", async () => {
  const { db, leituras } = bancoPorColunas({
    [COLUNAS_DA_JANELA]: { data: CONFIG },
    [COLUNAS_DA_JANELA_DO_FORNECEDOR]: { error: { message: "column agenda_config.modo_fornecedor does not exist", code: "42703" } },
  });
  const { provider, enviados } = provedorDeMentira();
  const r = await enviarLote(db, provider, [
    item("1", "agenda-equipe", "2026-10-28T10:00:00"),
    forn("2", "2026-10-28T10:00:00"),
    item("3", "reply-router", "2026-10-28T10:00:00"),
    forn("4", "2026-10-28T10:00:00"),
  ], { delayMs: 0, agora: () => brt("2026-10-28T10:01:00") });
  assertEquals(r.map((x) => [x.id, x.ok, x.janela_da_agenda ?? null]),
    [["1", true, null], ["2", false, "janela"], ["3", true, null], ["4", false, "janela"]]);
  assertEquals(enviados, ["5547900000001", "5547900000003"]);
  assertStringIncludes(String(r[1].error), "não consegui ler a janela da agenda (column agenda_config.modo_fornecedor does not exist)");
  // uma leitura por janela, cada uma só das colunas dela
  assertEquals(leituras, [`agenda_config: ${COLUNAS_DA_JANELA}`, `agenda_config: ${COLUNAS_DA_JANELA_DO_FORNECEDOR}`]);
});

Deno.test("P5 nenhuma outra origem muda: com ou sem a linha do fornecedor no lote, as mesmas escritas e os mesmos envios (sábado às 23:00)", async () => {
  const outras = () => [
    item("1", null, "2026-10-31T22:59:00"),
    item("2", "reply-router", "2026-10-31T03:00:00"),
    item("3", "quote-reminders", "2026-10-30T23:59:00"),
    item("4", "agenda-cliente", "2026-10-31T23:00:00"),
    item("5", "comprovantes", "2026-10-31T23:00:00"),
  ];
  const sem = bancoPorColunas();
  const p1 = provedorDeMentira();
  const r1 = await enviarLote(sem.db, p1.provider, outras(), { delayMs: 0, agora: () => brt("2026-10-31T23:00:00") });
  const com = bancoPorColunas();
  const p2 = provedorDeMentira();
  const r2 = await enviarLote(com.db, p2.provider, [...outras(), forn("9", "2026-10-31T10:00:00")],
    { delayMs: 0, agora: () => brt("2026-10-31T23:00:00") });
  assertEquals(sem.leituras, []);
  assertEquals(r2.slice(0, 5), r1);
  assertEquals(p2.enviados, p1.enviados);
  assertEquals(p1.enviados.length, 5);
  for (const id of ["1", "2", "3", "4", "5"]) {
    const a = daFila(sem.escritas, id).map((e) => ({ ...e.valores, sent_at: "x" }));
    const b = daFila(com.escritas, id).map((e) => ({ ...e.valores, sent_at: "x" }));
    assertEquals(b, a, id);
  }
  // a do fornecedor (sábado, sem fornecedor_sabado) não saiu
  assertEquals(r2[5].janela_da_agenda, "fim_de_semana");
  assertEquals(com.leituras, [`agenda_config: ${COLUNAS_DA_JANELA_DO_FORNECEDOR}`]);
});
