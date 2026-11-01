// A rodada de quem faz o quê da Agenda de Produção no motor de 15 min (Fase 7c, P5 — 01/11/2026).
//
// O que estes testes protegem:
//  1. chama agenda_habilidade com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide a hora e o "uma vez
//     por dia": cedo e ja_rodou são o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations / agenda:habilidade),
//     e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261102100400) é pulada
//     calada — sem 96 linhas de erro por dia;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila;
//  6. index.ts chama o passo (0b2a) depois do aprendizado (0b2) e antes da vigia (0c), com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { habilidadeDaAgenda, RODADA_DA_HABILIDADE_AUSENTE } from "./agenda-habilidade.ts";

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
      if (nome === "agenda_habilidade") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, cedo: true, hora: "16:10:00" }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

const MODOS = { modo_habilidade: "sombra", modo_lider: "sombra", modo_habilidade_propor: "ligado" };
// qua 04/11/2026 22:30 de Brasília = 05/11 01:30 UTC: o dia ainda é 04/11.
const AS_22H30_BR = new Date("2026-11-05T01:30:00Z");
// qua 04/11/2026 16:15 de Brasília: o 1º tique depois de habilidade_hora (16:10).
const AS_16H15_BR = new Date("2026-11-04T19:15:00Z");
// qua 04/11/2026 10:00 de Brasília: antes da hora.
const AS_10H_BR = new Date("2026-11-04T13:00:00Z");

Deno.test("habilidade: chama agenda_habilidade com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { propor: { pessoas: 1, propostas: 1 }, vetos: { valeram: 0 }, conferir: { acoes: 0 }, medir: { sozinho_em_risco: 0 } };
  const { db, chamadas, tabelas } = mkDb({
    rodada: { data: { rodou: true, modos: MODOS, contagens, erros: 0, falhas: [] }, error: null },
  });
  const r = await habilidadeDaAgenda(db, AS_16H15_BR);
  assertEquals(chamadas("agenda_habilidade"), [{ p_hoje: "2026-11-04", p_agora: "2026-11-04T19:15:00.000Z" }]);
  assertEquals(r, { rodou: true, modos: MODOS, contagens, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("habilidade: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ rodada: { data: { rodou: false, ja_rodou: true }, error: null } });
  await habilidadeDaAgenda(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_habilidade")[0].p_hoje, "2026-11-04");
});

Deno.test("habilidade: cedo (antes de habilidade_hora) e ja_rodou (o 2º tique do dia) são o normal — sem erro nem log", async () => {
  const cedo = mkDb({});
  assertEquals(await habilidadeDaAgenda(cedo.db, AS_10H_BR), { rodou: false, cedo: true });
  assertEquals(cedo.chamadas("log_app_error"), []);
  const jaRodou = mkDb({ rodada: { data: { rodou: false, ja_rodou: true, modos: MODOS }, error: null } });
  assertEquals(await habilidadeDaAgenda(jaRodou.db, AS_22H30_BR), { rodou: false, ja_rodou: true, modos: MODOS });
  assertEquals(jaRodou.chamadas("log_app_error"), []);
});

Deno.test("habilidade: com os modos desligados o banco ainda é chamado (o prazo e a medida rodam sempre) e nada mais acontece aqui", async () => {
  const desligados = { modo_habilidade: "desligado", modo_lider: "desligado", modo_habilidade_propor: "desligado" };
  const { db, rpcs } = mkDb({
    rodada: { data: { rodou: true, modos: desligados, contagens: { vetos: { valeram: 0 }, medir: { sozinho_em_risco: 0 } }, erros: 0,
                      falhas: [] }, error: null },
  });
  const r = await habilidadeDaAgenda(db, AS_16H15_BR);
  assertEquals([r.rodou, r.modos], [true, desligados]);
  assertEquals(rpcs.map((x) => x.nome), ["agenda_habilidade"]);
});

Deno.test("habilidade: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:habilidade)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22023", message: "Faltam o dia e a hora da rodada de quem faz o quê." } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await habilidadeDaAgenda(db, AS_16H15_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:habilidade"]);
    assertStringIncludes(String(logs[0].p_message), "rodada de quem faz o quê:");
  }
});

Deno.test("habilidade: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_habilidade" } } });
    const r = await habilidadeDaAgenda(db, AS_16H15_BR);
    assertEquals(r, { pulado: RODADA_DA_HABILIDADE_AUSENTE });
    assertEquals(RODADA_DA_HABILIDADE_AUSENTE, "a migration 20261102100400 ainda não está no banco");
    assertEquals(chamadas("agenda_habilidade").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("habilidade: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, modos: MODOS, contagens: { propor: { pessoas: 1 } }, erros: 1,
                      falhas: [{ passo: "conferir", sqlstate: "22023", erro: "x" }] }, error: null },
  });
  const r = await habilidadeDaAgenda(db, AS_16H15_BR);
  assertEquals([r.erros, r.falhas], [1, [{ passo: "conferir", sqlstate: "22023", erro: "x" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("habilidade: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-habilidade.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_habilidade"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada de quem faz o quê (0b2a) roda depois do aprendizado (0b2) e antes da vigia (0c), com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const aprender = fonte.indexOf("agendaAprender = await aprenderDaAgenda(db, new Date());");
  const habilidade = fonte.indexOf("agendaHabilidade = await habilidadeDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, agoraDaVigia);");
  assertEquals(aprender > 0 && habilidade > aprender && vigia > habilidade, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaHabilidade", habilidade), vigia);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertEquals(fonte.includes("agenda_habilidade: agendaHabilidade"), true);
  assertEquals(fonte.includes('import { habilidadeDaAgenda } from "./agenda-habilidade.ts";'), true);
  // a ordem dos passos no cabeçalho: 0b2 → 0b2a → 0c
  const c0b2 = fonte.indexOf("//   0b2. "), c0b2a = fonte.indexOf("//   0b2a. "), c0c = fonte.indexOf("//   0c. ");
  assertEquals(c0b2 > 0 && c0b2a > c0b2 && c0c > c0b2a, true);
});
