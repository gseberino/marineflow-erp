// A rotina da equipe e da diária da Agenda de Produção no motor de 15 min (Fase 3, P4 — 24/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_rotina_rodar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:rotina), e a vigia e as regras seguem;
//  3. NADA vai à equipe daqui: a ficha, a confirmação e o "como foi hoje?" são enfileirados pelo banco (com o modo, a janela
//     e o teto conferidos lá). O TS só leva os acordes ao dono, e só quando o banco os devolve (ele só devolve com
//     modo_vigia = 'ligado' e a ação executada): em sombra ou desligado nada sai;
//  4. o acorde vai pelo MESMO envio da vigia (chave agenda:<ação>, só das 08 às 20h sem o portão, a ação contada).
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { rodarRotinaDaAgenda } from "./agenda-rotina.ts";
import { PORTAO_DESLIGADO } from "../_shared/uma-voz/registrar.ts";

interface Cena {
  rotina?: { data: unknown; error: unknown } | "lança";
  fila?: { code?: string; message?: string } | null;
}

function mkDb(cena: Cena) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const fila: Array<Record<string, unknown>> = [];
  const db = {
    from: (tabela: string) => {
      if (tabela !== "whatsapp_send_queue") throw new Error(`tabela inesperada: ${tabela}`);
      return {
        insert: (linha: Record<string, unknown>) => {
          fila.push(linha);
          return Promise.resolve({ error: cena.fila ?? null });
        },
      };
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      if (nome === "agenda_rotina_rodar") {
        if (cena.rotina === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rotina ?? { data: { rodou: false, acordes: [] }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, fila, chamadas };
}

const DONO = { id: "u-dono", phone: "5547999990000" };
// a voz única desligada: o acorde vai "como sempre" (fila direta, 08–20h)
const deps = (dono: typeof DONO | null = DONO) => ({
  lerPortao: () => Promise.resolve({ ...PORTAO_DESLIGADO }),
  lerDono: () => Promise.resolve(dono),
});

const ACORDE = {
  chave: "agenda:acao-9", assunto: "equipe:roberto", acao_id: "acao-9", os: "os-69", perda_em: "2026-11-03",
  texto: "O Roberto não respondeu à confirmação de hoje até as 9h. Mudei a agenda de hoje: … *desfaz Vanderlei* volta como estava.",
};

// ter 03/11/2026 22:30 de Brasília = 04/11 01:30 UTC: o dia ainda é 03/11.
const AS_22H30_BR = new Date("2026-11-04T01:30:00Z");
// ter 03/11/2026 09:00 de Brasília (dentro da janela de acordar).
const AS_9H_BR = new Date("2026-11-03T12:00:00Z");

Deno.test("rotina: chama agenda_rotina_rodar com o dia de Brasília e a hora, e devolve o resumo", async () => {
  const { db, chamadas, fila } = mkDb({
    rotina: { data: { rodou: true, erros: 0, falhas: [], modos: { equipe: "sombra", diaria: "sombra" },
                      contagens: { ficha: { dia: "2026-11-04", por_estado: { registrada: 1 } } }, acordes: [] }, error: null },
  });
  const r = await rodarRotinaDaAgenda(db, AS_22H30_BR, deps());
  assertEquals(chamadas("agenda_rotina_rodar"), [{ p_hoje: "2026-11-03", p_agora: "2026-11-04T01:30:00.000Z" }]);
  assertEquals(r, {
    rodou: true, modos: { equipe: "sombra", diaria: "sombra" }, erros: 0, falhas: [],
    contagens: { ficha: { dia: "2026-11-04", por_estado: { registrada: 1 } } },
  });
  // em sombra a ficha fica só registrada no banco: o TS não põe nada na fila
  assertEquals(fila, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("rotina: os modos desligados — o banco não roda e nada mais é chamado", async () => {
  const { db, rpcs, fila } = mkDb({ rotina: { data: { rodou: false, modos: { equipe: "desligado", diaria: "desligado" }, acordes: [] }, error: null } });
  const r = await rodarRotinaDaAgenda(db, AS_9H_BR, deps());
  assertEquals(r.rodou, false);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_rotina_rodar"]);
  assertEquals(fila, []);
});

Deno.test("rotina: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:rotina)", async () => {
  for (const rotina of [{ data: null, error: { code: "PGRST202", message: "Could not find the function agenda_rotina_rodar" } }, "lança" as const]) {
    const { db, chamadas, fila } = mkDb({ rotina });
    const r = await rodarRotinaDaAgenda(db, AS_9H_BR, deps());
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:rotina"]);
    assertStringIncludes(String(logs[0].p_message), "rotina da agenda:");
    assertEquals(fila, []);
  }
});

Deno.test("rotina: sem acorde do banco (sombra, ou a vigia não ligada), nada vai à fila nem ao dono", async () => {
  const { db, rpcs, fila } = mkDb({ rotina: { data: { rodou: true, erros: 0, acordes: [] }, error: null } });
  const r = await rodarRotinaDaAgenda(db, AS_9H_BR, deps());
  assertEquals(r.acordes, undefined);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_rotina_rodar"]);
  assertEquals(fila, []);
});

Deno.test("rotina: o acorde que o banco devolve vai ao dono pelo envio da vigia (chave agenda:<ação>) e a ação fica contada", async () => {
  const { db, chamadas, fila } = mkDb({ rotina: { data: { rodou: true, erros: 0, falhas: [], acordes: [ACORDE] }, error: null } });
  const r = await rodarRotinaDaAgenda(db, AS_9H_BR, deps());
  assertEquals(r.acordes, { enviados: 1, guardados: 0, fora_da_janela: 0, nao_saiu: 0 });
  assertEquals(fila.length, 1);
  assertEquals([fila[0].phone_normalized, fila[0].dedupe_key, fila[0].source, fila[0].message],
               [DONO.phone, "agenda:acao-9", "agenda", ACORDE.texto]);
  assertEquals(chamadas("agenda_acorde_registrado").map((a) => a.p_acao), ["acao-9"]);
});

Deno.test("rotina: o acorde fora das 08–20h não sai (o fechamento conta); sem dono com WhatsApp, nada sai", async () => {
  const { db, fila } = mkDb({ rotina: { data: { rodou: true, erros: 0, acordes: [ACORDE] }, error: null } });
  const r = await rodarRotinaDaAgenda(db, AS_22H30_BR, deps());
  assertEquals(r.acordes, { enviados: 0, guardados: 0, fora_da_janela: 1, nao_saiu: 0 });
  assertEquals(fila, []);
  const semDono = mkDb({ rotina: { data: { rodou: true, erros: 0, acordes: [ACORDE] }, error: null } });
  const r2 = await rodarRotinaDaAgenda(semDono.db, AS_9H_BR, deps(null));
  assertEquals(r2.acordes, { enviados: 0, guardados: 0, fora_da_janela: 0, nao_saiu: 1 });
  assertEquals(semDono.fila, []);
});

Deno.test("rotina: o TS nunca enfileira mensagem à equipe (source agenda-equipe é só do banco)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-rotina.ts", import.meta.url));
  assertEquals(fonte.includes("agenda-equipe"), false);
  assertEquals(/from\(["']whatsapp_send_queue["']\)/.test(fonte), false);
});
