// A rodada do local da Agenda de Produção no motor de 15 min (Fase 7d, P5 — 05/11/2026).
//
// O que estes testes protegem:
//  1. chama agenda_local_vigiar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide a hora e o "uma vez por dia": cedo,
//     ja_rodou e os 6 desligados são o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations / agenda:local), e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261107100400) é pulada calada — sem 96 linhas de
//     erro por dia;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila;
//  6. index.ts chama o passo (0b3) depois do aprendizado e de quem faz o quê e antes da vigia (0c), com try/catch próprio, e o põe no resumo; e a vigia não
//     chama a rodada: é uma RPC à parte.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { localDaAgenda, RODADA_DO_LOCAL_AUSENTE } from "./agenda-local.ts";

interface Cena {
  rodada?: { data: unknown; error: unknown } | "lança";
}

function mkDb(cena: Cena) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const tabelas: string[] = [];
  const db = {
    from: (tabela: string) => {
      tabelas.push(tabela);
      throw new Error(`tabela inesperada: ${tabela}`);
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      if (nome === "agenda_local_vigiar") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, cedo: true, hora: "16:15:00" }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

const MODOS = { calendario: "sombra", acesso: "sombra", bem: "sombra", patio: "sombra", viagem: "sombra", mesmo_local: "sombra" };
// qua 04/11/2026 22:30 de Brasília = 05/11 01:30 UTC: o dia ainda é 04/11.
const AS_22H30_BR = new Date("2026-11-05T01:30:00Z");
// qua 04/11/2026 16:15 de Brasília: o 1º tique a partir de local_hora.
const AS_16H15_BR = new Date("2026-11-04T19:15:00Z");
// qua 04/11/2026 10:00 de Brasília: antes da hora.
const AS_10H_BR = new Date("2026-11-04T13:00:00Z");

Deno.test("local: chama agenda_local_vigiar com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { combinar: { abertas: 1, criticas: 0, resolvidas: 0, descartadas: 0, em_teste: 2 }, conflitos: { calendario: 1 } };
  const { db, chamadas, tabelas } = mkDb({
    rodada: { data: { rodou: true, modos: MODOS, contagens, erros: 0, falhas: [] }, error: null },
  });
  const r = await localDaAgenda(db, AS_16H15_BR);
  assertEquals(chamadas("agenda_local_vigiar"), [{ p_hoje: "2026-11-04", p_agora: "2026-11-04T19:15:00.000Z" }]);
  assertEquals(r, { rodou: true, modos: MODOS, contagens, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("local: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ rodada: { data: { rodou: false, ja_rodou: true }, error: null } });
  await localDaAgenda(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_local_vigiar")[0].p_hoje, "2026-11-04");
});

Deno.test("local: cedo, ja_rodou e os 6 desligados são o normal — sem erro nem log", async () => {
  const cedo = mkDb({});
  assertEquals(await localDaAgenda(cedo.db, AS_10H_BR), { rodou: false, cedo: true });
  assertEquals(cedo.chamadas("log_app_error"), []);
  const jaRodou = mkDb({ rodada: { data: { rodou: false, ja_rodou: true, modos: MODOS }, error: null } });
  assertEquals(await localDaAgenda(jaRodou.db, AS_22H30_BR), { rodou: false, ja_rodou: true, modos: MODOS });
  assertEquals(jaRodou.chamadas("log_app_error"), []);
  const desligados = Object.fromEntries(Object.keys(MODOS).map((k) => [k, "desligado"]));
  const fora = mkDb({ rodada: { data: { rodou: false, modos: desligados }, error: null } });
  assertEquals(await localDaAgenda(fora.db, AS_16H15_BR), { rodou: false, modos: desligados });
  assertEquals(fora.chamadas("log_app_error"), []);
});

Deno.test("local: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:local)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22023", message: "Faltam o dia e a hora da rodada do local." } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await localDaAgenda(db, AS_16H15_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:local"]);
    assertStringIncludes(String(logs[0].p_message), "rodada do local:");
  }
});

Deno.test("local: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_local_vigiar" } } });
    const r = await localDaAgenda(db, AS_16H15_BR);
    assertEquals(r, { pulado: RODADA_DO_LOCAL_AUSENTE });
    assertEquals(RODADA_DO_LOCAL_AUSENTE, "a migration 20261107100400 ainda não está no banco");
    assertEquals(chamadas("agenda_local_vigiar").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("local: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modos: MODOS, contagens: { conflitos: {} }, erros: 1,
                      falhas: [{ passo: "combinar", sqlstate: "22023", erro: "x" }] }, error: null },
  });
  const r = await localDaAgenda(db, AS_16H15_BR);
  assertEquals([r.erros, r.falhas], [1, [{ passo: "combinar", sqlstate: "22023", erro: "x" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("local: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-local.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_local_vigiar"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada do local (0b3) roda depois do aprendizado e de quem faz o quê e antes da vigia (0c), com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const aprender = fonte.indexOf("agendaAprender = await aprenderDaAgenda(db, new Date());");
  const habilidade = fonte.indexOf("agendaHabilidade = await habilidadeDaAgenda(db, new Date());");
  const local = fonte.indexOf("agendaLocal = await localDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, agoraDaVigia);");
  assertEquals(aprender > 0 && habilidade > aprender && local > habilidade && vigia > local, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaLocal", local), vigia);
  assertStringIncludes(bloco, "try {");
  assertStringIncludes(bloco, "catch (e)");
  assertStringIncludes(fonte, "agenda_local: agendaLocal");
  assertStringIncludes(fonte, 'import { localDaAgenda } from "./agenda-local.ts";');
});
