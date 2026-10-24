// A vigia da Agenda de Produção no motor de 15 min (Fase 2, P3 — 24/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_vigiar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:vigia), e as regras seguem;
//  3. acorde só quando o banco devolve (ele só devolve com modo_vigia = 'ligado' e a ação executada): sem acorde, nada
//     vai à fila nem ao portão;
//  4. com a voz única ligada, o portão decide ANTES: 'acordar' vai pela fila (chave aviso:<id>) e a ação fica contada;
//     'guardar' é resolvido na hora (aviso_resolver: o fechamento já conta a mudança) e nada sai; portão ilegível =
//     manda como sempre (nunca calar por erro de leitura);
//  5. com a voz em sombra ou desligada, manda como sempre — só das 08 às 20h —, uma vez por ação (chave agenda:<ação>), e
//     em sombra registra depois;
//  6. sem dono com WhatsApp, nada sai.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { acordesValidos, enviarAcordesDaAgenda, linhaDoAcordeDireto, vigiarAgenda } from "./agenda-vigia.ts";
import { PORTAO_DESLIGADO, type PortaoDaRodada } from "../_shared/uma-voz/registrar.ts";
import { REGRAS_PADRAO } from "../_shared/uma-voz/portao.ts";

interface Cena {
  vigiar?: { data: unknown; error: unknown } | "lança";
  /** a resposta do aviso_registrar (o portão) */
  portao?: { data: unknown; error: unknown };
  /** o erro do insert na fila */
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
      if (nome === "agenda_vigiar") {
        if (cena.vigiar === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.vigiar ?? { data: { rodou: false, acordes: [] }, error: null });
      }
      if (nome === "aviso_registrar") return Promise.resolve(cena.portao ?? { data: { ok: true, decisao: "acordar", id: "aviso-1" }, error: null });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, fila, chamadas };
}

const DONO = { id: "u-dono", phone: "5547999990000" };
const portaoEm = (modo: PortaoDaRodada["modo"]): PortaoDaRodada => ({
  voz: modo ?? "desligado", modo, regras: { ...REGRAS_PADRAO }, freio: false,
});
const deps = (modo: PortaoDaRodada["modo"], dono: typeof DONO | null = DONO) => ({
  lerPortao: () => Promise.resolve(modo ? portaoEm(modo) : { ...PORTAO_DESLIGADO }),
  lerDono: () => Promise.resolve(dono),
});

const ACORDE = {
  chave: "agenda:acao-1", assunto: "os:os-69", acao_id: "acao-1", os: "os-69", perda_em: "2026-10-30",
  texto: "Mudei a agenda de amanhã: Vanderlei (OS-00069): de qui 29/10 para sex 30/10. *desfaz Vanderlei* volta como estava.",
};
const comAcorde = { data: { rodou: true, erros: 0, falhas: [], contagens: { publicacao: { publicou: false } }, acordes: [ACORDE] }, error: null };

// 23/10/2026 22:30 de Brasília = 24/10 01:30 UTC: o dia ainda é 23/10.
const AS_22H30_BR = new Date("2026-10-24T01:30:00Z");
// qui 29/10/2026 10:00 de Brasília (dentro da janela de acordar).
const AS_10H_BR = new Date("2026-10-29T13:00:00Z");
// qui 29/10/2026 21:00 de Brasília (fora da janela).
const AS_21H_BR = new Date("2026-10-30T00:00:00Z");

Deno.test("vigia: chama agenda_vigiar com o dia de Brasília e a hora, e devolve o resumo", async () => {
  const { db, chamadas } = mkDb({ vigiar: { data: { rodou: true, erros: 0, falhas: [], contagens: { poda: { apagadas: 0 } }, acordes: [] }, error: null } });
  const r = await vigiarAgenda(db, AS_22H30_BR, deps(null));
  assertEquals(chamadas("agenda_vigiar"), [{ p_hoje: "2026-10-23", p_agora: "2026-10-24T01:30:00.000Z" }]);
  assertEquals(r, { rodou: true, modos: undefined, erros: 0, falhas: [], contagens: { poda: { apagadas: 0 } } });
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("vigia: os modos desligados — o banco não roda e nada mais é chamado", async () => {
  const { db, rpcs, fila } = mkDb({ vigiar: { data: { rodou: false, modos: { proposta: "desligado", vigia: "desligado" }, acordes: [] }, error: null } });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
  assertEquals(r.rodou, false);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_vigiar"]);
  assertEquals(fila, []);
});

Deno.test("vigia: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:vigia)", async () => {
  for (const vigiar of [{ data: null, error: { code: "42883", message: "function agenda_vigiar does not exist" } }, "lança" as const]) {
    const { db, chamadas, fila } = mkDb({ vigiar });
    const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:vigia"]);
    assertStringIncludes(String(logs[0].p_message), "vigia da agenda:");
    assertEquals(fila, []);
  }
});

Deno.test("vigia: a dependência que lança também não derruba o motor", async () => {
  const { db, chamadas } = mkDb({ vigiar: comAcorde });
  const r = await vigiarAgenda(db, AS_10H_BR, { lerPortao: () => Promise.reject(new Error("quebrou")), lerDono: () => Promise.resolve(DONO) });
  assertEquals(typeof r.erro, "string");
  assertEquals(chamadas("log_app_error").length, 1);
});

Deno.test("vigia: sem acorde do banco (sombra, ou vigia não ligada), nada vai à fila nem ao portão", async () => {
  const { db, rpcs, fila } = mkDb({ vigiar: { data: { rodou: true, erros: 0, acordes: [] }, error: null } });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
  assertEquals(r.acordes, undefined);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_vigiar"]);
  assertEquals(fila, []);
});

Deno.test("acorde, voz ligada: o portão acorda → vai pela fila com a chave aviso:<id> e a ação fica contada", async () => {
  const { db, fila, chamadas } = mkDb({ vigiar: comAcorde, portao: { data: { ok: true, decisao: "acordar", id: "aviso-9", cartao: true }, error: null } });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
  assertEquals(r.acordes, { enviados: 1, guardados: 0, fora_da_janela: 0, nao_saiu: 0 });
  const p = chamadas("aviso_registrar")[0].p as Record<string, unknown>;
  assertEquals([p.fonte, p.chave, p.assunto, p.destino, p.modo, p.phone], ["agenda", "agenda:acao-1", "os:os-69", "acorde", "ligado", DONO.phone]);
  assertEquals(fila.length, 1);
  assertEquals([fila[0].dedupe_key, fila[0].source, fila[0].message, fila[0].phone_normalized], ["aviso:aviso-9", "agenda", ACORDE.texto, DONO.phone]);
  assertEquals(chamadas("agenda_acorde_registrado"), [{ p_acao: "acao-1", p_aviso: "aviso-9", p_enviado: true, p_agora: AS_10H_BR.toISOString() }]);
});

Deno.test("acorde, voz ligada: o portão guarda → resolvido na hora (o fechamento já conta) e nada sai", async () => {
  const { db, fila, chamadas } = mkDb({ vigiar: comAcorde, portao: { data: { ok: true, decisao: "guardar", id: "aviso-7", motivo: "limite_do_dia" }, error: null } });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
  assertEquals(r.acordes, { enviados: 0, guardados: 1, fora_da_janela: 0, nao_saiu: 0 });
  assertEquals(fila, []);
  assertEquals(chamadas("aviso_resolver"), [{ p: { phone: DONO.phone, modo: "ligado", ids: ["aviso-7"], motivo: "agenda_no_fechamento" } }]);
  assertEquals(chamadas("agenda_acorde_registrado"), []);
});

Deno.test("acorde, voz ligada: 'repetido' ou 'acabar' não sai; portão ilegível manda como sempre (nunca calar por erro)", async () => {
  for (const decisao of ["repetido", "acabar"]) {
    const { db, fila } = mkDb({ vigiar: comAcorde, portao: { data: { ok: true, decisao, id: "aviso-3", antes: "acordar" }, error: null } });
    const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
    assertEquals(r.acordes?.nao_saiu, 1, decisao);
    assertEquals(fila, []);
  }
  const { db, fila, chamadas } = mkDb({ vigiar: comAcorde, portao: { data: null, error: { message: "timeout" } } });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("ligado"));
  assertEquals(r.acordes?.enviados, 1);
  assertEquals(fila.map((l) => l.dedupe_key), ["agenda:acao-1"]);
  assertEquals(chamadas("agenda_acorde_registrado").map((a) => a.p_aviso), [null]);
});

Deno.test("acorde, voz em sombra: manda como sempre (uma vez por ação) e registra no portão depois", async () => {
  const { db, fila, chamadas, rpcs } = mkDb({ vigiar: comAcorde });
  const r = await vigiarAgenda(db, AS_10H_BR, deps("sombra"));
  assertEquals(r.acordes, { enviados: 1, guardados: 0, fora_da_janela: 0, nao_saiu: 0 });
  assertEquals(fila.length, 1);
  assertEquals([fila[0].dedupe_key, fila[0].source, fila[0].priority], ["agenda:acao-1", "agenda", 1]);
  assertEquals(chamadas("agenda_acorde_registrado").length, 1);
  // a ordem: manda, marca, registra em sombra
  assertEquals(rpcs.map((x) => x.nome), ["agenda_vigiar", "agenda_acorde_registrado", "aviso_registrar"]);
  assertEquals((chamadas("aviso_registrar")[0].p as Record<string, unknown>).modo, "sombra");
});

Deno.test("acorde, voz desligada: manda como sempre e não registra no portão", async () => {
  const { db, fila, chamadas } = mkDb({ vigiar: comAcorde });
  const r = await vigiarAgenda(db, AS_10H_BR, deps(null));
  assertEquals(r.acordes?.enviados, 1);
  assertEquals(fila.length, 1);
  assertEquals(chamadas("aviso_registrar"), []);
});

Deno.test("acorde fora das 08–20h (sem portão ligado): não sai, fica para o fechamento", async () => {
  const { db, fila, chamadas } = mkDb({ vigiar: comAcorde });
  const r = await vigiarAgenda(db, AS_21H_BR, deps("sombra"));
  assertEquals(r.acordes, { enviados: 0, guardados: 0, fora_da_janela: 1, nao_saiu: 0 });
  assertEquals(fila, []);
  assertEquals(chamadas("agenda_acorde_registrado"), []);
});

Deno.test("acorde: a mesma ação já na fila (23505) conta como enviada; outro erro da fila não marca", async () => {
  const dup = mkDb({ vigiar: comAcorde, fila: { code: "23505", message: "duplicate key" } });
  assertEquals((await vigiarAgenda(dup.db, AS_10H_BR, deps(null))).acordes?.enviados, 1);
  const ruim = mkDb({ vigiar: comAcorde, fila: { code: "42501", message: "permission denied" } });
  const r = await vigiarAgenda(ruim.db, AS_10H_BR, deps(null));
  assertEquals(r.acordes, { enviados: 0, guardados: 0, fora_da_janela: 0, nao_saiu: 1 });
  assertEquals(ruim.chamadas("agenda_acorde_registrado"), []);
});

Deno.test("acorde sem dono com WhatsApp: nada sai", async () => {
  const { db, fila } = mkDb({ vigiar: comAcorde });
  const r = await enviarAcordesDaAgenda(db, acordesValidos([ACORDE]), AS_10H_BR, deps("ligado", null));
  assertEquals(r, { enviados: 0, guardados: 0, fora_da_janela: 0, nao_saiu: 1 });
  assertEquals(fila, []);
});

Deno.test("acordesValidos: só o que tem a ação e o texto; chave e assunto de sempre quando faltam", () => {
  assertEquals(acordesValidos(null), []);
  assertEquals(acordesValidos([{ texto: "sem ação" }, { acao_id: "a", texto: "  " }, "lixo"]), []);
  assertEquals(acordesValidos([{ acao_id: "a", texto: "ok" }]),
    [{ acao_id: "a", texto: "ok", chave: "agenda:a", assunto: "agenda:a", os: null, perda_em: null }]);
});

Deno.test("linhaDoAcordeDireto: prioridade 1, tentativas só até as 20h, uma por ação", () => {
  const l = linhaDoAcordeDireto({ phone: DONO.phone, texto: "x", acaoId: "acao-5", agora: AS_10H_BR });
  assertEquals([l.dedupe_key, l.source, l.priority, l.source_ref_id], ["agenda:acao-5", "agenda", 1, "acao-5"]);
  assertEquals(typeof l.max_attempts === "number" && (l.max_attempts as number) >= 1, true);
});
