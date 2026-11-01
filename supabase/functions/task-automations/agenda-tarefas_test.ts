// A rodada das etapas da Agenda de Produção (as tarefas do dia) no motor de 15 min (Fase 7c, P8 — 01/11/2026).
//
// O que estes testes protegem:
//  1. chama agenda_tarefas_rodar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide o modo, o
//     congelar das 19:30 e o diário das 16:20), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations / agenda:tarefas),
//     e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261102100550) é pulada
//     calada — sem 96 linhas de erro por dia;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila;
//  6. index.ts chama o passo (0a) depois do material (0) e antes da rotina (0b), com o MESMO instante da rotina (o congelar das
//     19:30 vem antes da ficha do mesmo tique), com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { RODADA_DAS_TAREFAS_AUSENTE, tarefasDaAgenda } from "./agenda-tarefas.ts";

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
      if (nome === "agenda_tarefas_rodar") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, modo: "desligado" }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

// qua 04/11/2026 22:30 de Brasília = 05/11 01:30 UTC: o dia ainda é 04/11.
const AS_22H30_BR = new Date("2026-11-05T01:30:00Z");
// qua 04/11/2026 19:30 de Brasília: o tique que congela o plano de amanhã, antes da ficha.
const AS_19H30_BR = new Date("2026-11-04T22:30:00Z");

Deno.test("tarefas: chama agenda_tarefas_rodar com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { sincronizar: { os: 2, mudou: 1 }, congelar: { linhas: 4 }, conferir: { os: 0 } };
  const { db, chamadas, tabelas } = mkDb({
    rodada: { data: { rodou: true, modo: "sombra", contagens, erros: 0, falhas: [], gravou: true }, error: null },
  });
  const r = await tarefasDaAgenda(db, AS_19H30_BR);
  assertEquals(chamadas("agenda_tarefas_rodar"), [{ p_hoje: "2026-11-04", p_agora: "2026-11-04T22:30:00.000Z" }]);
  assertEquals(r, { rodou: true, modo: "sombra", contagens, gravou: true, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("tarefas: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ rodada: { data: { rodou: true, modo: "ligado", contagens: {}, erros: 0, falhas: [], gravou: false }, error: null } });
  await tarefasDaAgenda(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_tarefas_rodar")[0].p_hoje, "2026-11-04");
});

Deno.test("tarefas: com modo_tarefas desligado o banco devolve { rodou: false } — o normal, sem erro nem log", async () => {
  const { db, chamadas, rpcs } = mkDb({});
  assertEquals(await tarefasDaAgenda(db, AS_19H30_BR), { rodou: false, modo: "desligado" });
  assertEquals(rpcs.map((x) => x.nome), ["agenda_tarefas_rodar"]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("tarefas: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:tarefas)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22023", message: "Faltam o dia e a hora da rodada das etapas." } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await tarefasDaAgenda(db, AS_19H30_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:tarefas"]);
    assertStringIncludes(String(logs[0].p_message), "rodada das etapas:");
  }
});

Deno.test("tarefas: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_tarefas_rodar" } } });
    const r = await tarefasDaAgenda(db, AS_19H30_BR);
    assertEquals(r, { pulado: RODADA_DAS_TAREFAS_AUSENTE });
    assertEquals(RODADA_DAS_TAREFAS_AUSENTE, "a migration 20261102100550 ainda não está no banco");
    assertEquals(chamadas("agenda_tarefas_rodar").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("tarefas: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modo: "ligado", contagens: { sincronizar: { os: 1 } }, erros: 1,
                      falhas: [{ passo: "congelar", sqlstate: "P0001", erro: "x" }], gravou: true }, error: null },
  });
  const r = await tarefasDaAgenda(db, AS_19H30_BR);
  assertEquals([r.erros, r.falhas], [1, [{ passo: "congelar", sqlstate: "P0001", erro: "x" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("tarefas: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-tarefas.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_tarefas_rodar"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada das etapas (0a) roda depois do material (0) e antes da rotina (0b), com o mesmo instante dela, try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const material = fonte.indexOf("agendaMaterial = await sincronizarMaterialDaAgenda(db);");
  const instante = fonte.indexOf("const agoraDaRotina = new Date();");
  const tarefas = fonte.indexOf("agendaTarefas = await tarefasDaAgenda(db, agoraDaRotina);");
  const rotina = fonte.indexOf("agendaRotina = await rodarRotinaDaAgenda(db, agoraDaRotina);");
  assertEquals(material > 0 && instante > material && tarefas > instante && rotina > tarefas, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaTarefas", tarefas), rotina);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_tarefas: agendaTarefas"), true);
  assertEquals(fonte.includes('import { tarefasDaAgenda } from "./agenda-tarefas.ts";'), true);
  // a ordem dos passos no cabeçalho: 0 → 0a → 0b
  const c0 = fonte.indexOf("//   0. "), c0a = fonte.indexOf("//   0a. "), c0b = fonte.indexOf("//   0b. ");
  assertEquals(c0 > 0 && c0a > c0 && c0b > c0a, true);
});
