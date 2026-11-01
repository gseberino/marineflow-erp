// A rodada da semana da equipe da Agenda de Produção no motor de 15 min (Fase 7b, P3 — 31/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_equipe_semana com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide o modo, a hora e
//     o "uma vez por dia": { rodou: false } com os modos desligados é o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:equipe-semana), e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261101100200) é pulada
//     calada — sem 96 linhas de erro por dia;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila (o banco registra e enfileira);
//  6. index.ts chama o passo (0b1) depois da rotina (0b) e antes do aprendizado (0b2), com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { RODADA_DA_SEMANA_AUSENTE, rodarSemanaDaEquipe } from "./agenda-equipe-semana.ts";

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
      if (nome === "agenda_equipe_semana") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, modos: { dias: "desligado", cadastro: "desligado" } }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

// qui 05/11/2026 16:45 de Brasília = 19:45 UTC: o 1º tique da pergunta da semana.
const AS_16H45_BR = new Date("2026-11-05T19:45:00Z");
// qui 05/11/2026 22:30 de Brasília = 06/11 01:30 UTC: o dia ainda é 05/11.
const AS_22H30_BR = new Date("2026-11-06T01:30:00Z");

Deno.test("semana da equipe: chama agenda_equipe_semana com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { diario: true, cadastro: { chamada: 1 }, perguntar: { enfileirada: 1, dono: "sem_motivo" } };
  const modos = { dias: "ligado", cadastro: "ligado" };
  const { db, chamadas, tabelas } = mkDb({ rodada: { data: { rodou: true, modos, contagens, erros: 0, falhas: [] }, error: null } });
  const r = await rodarSemanaDaEquipe(db, AS_16H45_BR);
  assertEquals(chamadas("agenda_equipe_semana"), [{ p_hoje: "2026-11-05", p_agora: "2026-11-05T19:45:00.000Z" }]);
  assertEquals(r, { rodou: true, modos, contagens, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("semana da equipe: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({});
  await rodarSemanaDaEquipe(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_equipe_semana")[0].p_hoje, "2026-11-05");
});

Deno.test("semana da equipe: com os modos desligados (rodou false) é o normal — sem erro nem log", async () => {
  const { db, chamadas } = mkDb({});
  assertEquals(await rodarSemanaDaEquipe(db, AS_16H45_BR), { rodou: false, modos: { dias: "desligado", cadastro: "desligado" } });
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("semana da equipe: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:equipe-semana)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22004", message: "agenda_equipe_semana: sem o dia ou a hora" } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await rodarSemanaDaEquipe(db, AS_16H45_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:equipe-semana"]);
    assertStringIncludes(String(logs[0].p_message), "rodada da semana da equipe:");
  }
});

Deno.test("semana da equipe: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_equipe_semana" } } });
    const r = await rodarSemanaDaEquipe(db, AS_16H45_BR);
    assertEquals(r, { pulado: RODADA_DA_SEMANA_AUSENTE });
    assertEquals(RODADA_DA_SEMANA_AUSENTE, "a migration 20261101100200 ainda não está no banco");
    assertEquals(chamadas("agenda_equipe_semana").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("semana da equipe: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modos: { dias: "sombra", cadastro: "sombra" }, contagens: {}, erros: 1,
                      falhas: [{ passo: "fechar", sqlstate: "22023", erro: "x" }] }, error: null },
  });
  const r = await rodarSemanaDaEquipe(db, AS_16H45_BR);
  assertEquals([r.erros, r.falhas], [1, [{ passo: "fechar", sqlstate: "22023", erro: "x" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("semana da equipe: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-equipe-semana.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_equipe_semana"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada da semana da equipe (0b1) roda depois da rotina (0b) e antes do aprendizado (0b2), com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const rotina = fonte.indexOf("agendaRotina = await rodarRotinaDaAgenda(db, agoraDaRotina);");
  const semana = fonte.indexOf("agendaEquipeSemana = await rodarSemanaDaEquipe(db, new Date());");
  const aprender = fonte.indexOf("agendaAprender = await aprenderDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, agoraDaVigia);");
  assertEquals(rotina > 0 && semana > rotina && aprender > semana && vigia > aprender, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaEquipeSemana", semana), aprender);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_equipe_semana: agendaEquipeSemana"), true);
  assertEquals(fonte.includes('import { rodarSemanaDaEquipe } from "./agenda-equipe-semana.ts";'), true);
  // a ordem dos passos no cabeçalho: 0b → 0b1 → 0b2
  const c0b = fonte.indexOf("//   0b. "), c0b1 = fonte.indexOf("//   0b1. "), c0b2 = fonte.indexOf("//   0b2. ");
  assertEquals(c0b > 0 && c0b1 > c0b && c0b2 > c0b1, true);
});
