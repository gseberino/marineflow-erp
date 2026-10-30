// A rodada do aprendizado da Agenda de Produção no motor de 15 min (Fase 6, P8 — 28/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_aprender com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide a hora e o
//     "uma vez por dia": cedo e ja_rodou são o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:aprender), e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261029100600) é
//     pulada calada — sem 96 linhas de erro por dia;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila;
//  6. index.ts chama o passo depois da rotina e antes da vigia, com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aprenderDaAgenda, RODADA_DO_APRENDIZADO_AUSENTE } from "./agenda-aprender.ts";

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
      if (nome === "agenda_aprender") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, cedo: true, modo: "sombra", hora: "16:00:00" }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

// sex 30/10/2026 22:30 de Brasília = 31/10 01:30 UTC: o dia ainda é 30/10.
const AS_22H30_BR = new Date("2026-10-31T01:30:00Z");
// sex 30/10/2026 16:05 de Brasília: o 1º tique depois de aprender_hora.
const AS_16H05_BR = new Date("2026-10-30T19:05:00Z");
// sex 30/10/2026 10:00 de Brasília: antes da hora.
const AS_10H_BR = new Date("2026-10-30T13:00:00Z");

Deno.test("aprender: chama agenda_aprender com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { congelar: { congeladas: 1, sem_dias: 0 }, medir: { medidas: 3, validas: 2 }, fator: { chaves: 4 } };
  const { db, chamadas, tabelas } = mkDb({
    rodada: { data: { rodou: true, modo: "sombra", ligados: [], semanal: false, contagens, erros: 0, falhas: [] }, error: null },
  });
  const r = await aprenderDaAgenda(db, AS_16H05_BR);
  assertEquals(chamadas("agenda_aprender"), [{ p_hoje: "2026-10-30", p_agora: "2026-10-30T19:05:00.000Z" }]);
  assertEquals(r, { rodou: true, modo: "sombra", ligados: [], semanal: false, contagens, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("aprender: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ rodada: { data: { rodou: false, ja_rodou: true, modo: "ligado" }, error: null } });
  await aprenderDaAgenda(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_aprender")[0].p_hoje, "2026-10-30");
});

Deno.test("aprender: cedo (antes de aprender_hora) e ja_rodou (o 2º tique do dia) são o normal — sem erro nem log", async () => {
  const cedo = mkDb({});
  assertEquals(await aprenderDaAgenda(cedo.db, AS_10H_BR), { rodou: false, cedo: true, modo: "sombra" });
  assertEquals(cedo.chamadas("log_app_error"), []);
  const jaRodou = mkDb({ rodada: { data: { rodou: false, ja_rodou: true, modo: "desligado" }, error: null } });
  assertEquals(await aprenderDaAgenda(jaRodou.db, AS_22H30_BR), { rodou: false, ja_rodou: true, modo: "desligado" });
  assertEquals(jaRodou.chamadas("log_app_error"), []);
});

Deno.test("aprender: com o modo desligado o banco ainda é chamado (a medição roda sempre) e nada mais acontece aqui", async () => {
  const { db, rpcs } = mkDb({
    rodada: { data: { rodou: true, modo: "desligado", ligados: [], semanal: false,
                      contagens: { congelar: { congeladas: 0 }, medir: { medidas: 1 } }, erros: 0, falhas: [] }, error: null },
  });
  const r = await aprenderDaAgenda(db, AS_16H05_BR);
  assertEquals([r.rodou, r.modo], [true, "desligado"]);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_aprender"]);
});

Deno.test("aprender: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:aprender)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22023", message: "agenda_aprender: sem o dia de hoje" } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await aprenderDaAgenda(db, AS_16H05_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:aprender"]);
    assertStringIncludes(String(logs[0].p_message), "rodada do aprendizado:");
  }
});

Deno.test("aprender: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_aprender" } } });
    const r = await aprenderDaAgenda(db, AS_16H05_BR);
    assertEquals(r, { pulado: RODADA_DO_APRENDIZADO_AUSENTE });
    assertEquals(RODADA_DO_APRENDIZADO_AUSENTE, "a migration 20261029100600 ainda não está no banco");
    assertEquals(chamadas("agenda_aprender").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("aprender: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modo: "ligado", ligados: ["fator"], semanal: true, contagens: {}, erros: 1,
                      falhas: [{ passo: "fornecedor", sqlstate: "22023", erro: "x" }] }, error: null },
  });
  const r = await aprenderDaAgenda(db, AS_16H05_BR);
  assertEquals([r.erros, r.falhas, r.ligados, r.semanal], [1, [{ passo: "fornecedor", sqlstate: "22023", erro: "x" }], ["fator"], true]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("aprender: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-aprender.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_aprender"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada do aprendizado roda depois da rotina e antes da vigia, com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const rotina = fonte.indexOf("agendaRotina = await rodarRotinaDaAgenda(db, new Date());");
  const aprender = fonte.indexOf("agendaAprender = await aprenderDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, agoraDaVigia);");
  const cliente = fonte.indexOf("agendaClienteVigia = await vigiarClienteDaAgenda(db, new Date());");
  const regras = fonte.indexOf("const rules = await runRules(db, settings);");
  assertEquals(rotina > 0 && aprender > rotina && vigia > aprender && cliente > vigia && regras > cliente, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaAprender", aprender), vigia);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_aprender: agendaAprender"), true);
  assertEquals(fonte.includes('import { aprenderDaAgenda } from "./agenda-aprender.ts";'), true);
});
