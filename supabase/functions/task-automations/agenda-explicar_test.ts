// A rodada explicar da Agenda de Produção no motor de 15 min (Fase 7g, P5 — 12/11/2026).
//
// O que estes testes protegem:
//  1. chama agenda_explicar_rodar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide a hora, o domingo, o modo e o "uma vez
//     por dia": desligado, domingo, cedo, ja_rodou e nada são o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations / agenda:explicar), e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration 20261112100400) é pulada calada;
//  4. o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui; o parou_no (o tempo acabou) volta também;
//  5. NADA sai daqui: o passo não lê o modo, não escreve em tabela nenhuma e não põe nada na fila;
//  6. index.ts chama o passo depois da rodada do cliente e antes da rodada comunicar (R9.5-21), com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { explicarDaAgenda, RODADA_EXPLICAR_AUSENTE } from "./agenda-explicar.ts";

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
      if (nome === "agenda_explicar_rodar") {
        if (cena.rodada === "lança") return Promise.reject(new Error("conexão caiu"));
        return Promise.resolve(cena.rodada ?? { data: { rodou: false, cedo: true, hora: "16:35:00" }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((r) => r.nome === nome).map((r) => r.args);
  return { db, rpcs, tabelas, chamadas };
}

// qui 12/11/2026 22:30 de Brasília = 13/11 01:30 UTC: o dia ainda é 12/11.
const AS_22H30_BR = new Date("2026-11-13T01:30:00Z");
// qui 12/11/2026 16:36 de Brasília: o 1º tique depois de explicar_hora.
const AS_16H36_BR = new Date("2026-11-12T19:36:00Z");
// qui 12/11/2026 10:00 de Brasília: antes da hora.
const AS_10H_BR = new Date("2026-11-12T13:00:00Z");

Deno.test("explicar: chama agenda_explicar_rodar com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const contagens = { marcacoes: { registradas: 2, decididas: { aceita: 1 } }, tipos: { classes: 1, teria: 0, espera_ok: 0, voltaram: 0 } };
  const modos = { porque: "sombra", rebaixar: "sombra", placar: "sombra" };
  const { db, chamadas, tabelas } = mkDb({
    rodada: { data: { rodou: true, diaria: true, contagens, modos, erros: 0, falhas: [] }, error: null },
  });
  const r = await explicarDaAgenda(db, AS_16H36_BR);
  assertEquals(chamadas("agenda_explicar_rodar"), [{ p_hoje: "2026-11-12", p_agora: "2026-11-12T19:36:00.000Z" }]);
  assertEquals(r, { rodou: true, contagens, modos, erros: 0, falhas: [] });
  assertEquals(tabelas, []);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("explicar: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ rodada: { data: { rodou: false, ja_rodou: true }, error: null } });
  await explicarDaAgenda(db, AS_22H30_BR);
  assertEquals(chamadas("agenda_explicar_rodar")[0].p_hoje, "2026-11-12");
});

Deno.test("explicar: desligado, domingo, cedo, ja_rodou e nada são o normal — sem erro nem log", async () => {
  const cedo = mkDb({});
  assertEquals(await explicarDaAgenda(cedo.db, AS_10H_BR), { rodou: false, cedo: true });
  for (const [data, esperado] of [
    [{ rodou: false, desligado: true }, { rodou: false, desligado: true }],
    [{ rodou: false, domingo: true }, { rodou: false, domingo: true }],
    [{ rodou: false, ja_rodou: true }, { rodou: false, ja_rodou: true }],
    [{ rodou: false, nada: true }, { rodou: false, nada: true }],
  ] as const) {
    const x = mkDb({ rodada: { data, error: null } });
    assertEquals(await explicarDaAgenda(x.db, AS_22H30_BR), esperado);
    assertEquals(x.chamadas("log_app_error"), []);
  }
  assertEquals(cedo.chamadas("log_app_error"), []);
});

Deno.test("explicar: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:explicar)", async () => {
  for (const rodada of [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } },
                        { data: null, error: { code: "22023", message: "Faltam o dia e a hora da rodada explicar." } },
                        "lança" as const]) {
    const { db, chamadas } = mkDb({ rodada });
    const r = await explicarDaAgenda(db, AS_16H36_BR);
    assertEquals(typeof r.erro, "string");
    const logs = chamadas("log_app_error");
    assertEquals(logs.length, 1);
    assertEquals([logs[0].p_context, logs[0].p_action], ["task-automations", "agenda:explicar"]);
    assertStringIncludes(String(logs[0].p_message), "rodada explicar:");
  }
});

Deno.test("explicar: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ rodada: { data: null, error: { code, message: "Could not find the function agenda_explicar_rodar" } } });
    const r = await explicarDaAgenda(db, AS_16H36_BR);
    assertEquals(r, { pulado: RODADA_EXPLICAR_AUSENTE });
    assertEquals(RODADA_EXPLICAR_AUSENTE, "a migration 20261112100400 ainda não está no banco");
    assertEquals(chamadas("agenda_explicar_rodar").length, 1);
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("explicar: o passo que falhou no banco e o parou_no voltam no resumo (o banco já registrou) e não geram outra linha aqui", async () => {
  const { db, chamadas } = mkDb({
    rodada: { data: { rodou: true, diaria: true, contagens: { marcacoes: { registradas: 0, decididas: {} } }, modos: {}, erros: 1,
                      falhas: [{ passo: "tipos", sqlstate: "57014", erro: "x" }], parou_no: "tipos" }, error: null },
  });
  const r = await explicarDaAgenda(db, AS_16H36_BR);
  assertEquals([r.erros, r.falhas, r.parou_no], [1, [{ passo: "tipos", sqlstate: "57014", erro: "x" }], "tipos"]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("explicar: o TS não lê o modo, não escreve em tabela e não manda nada (o banco decide tudo)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-explicar.ts", import.meta.url));
  // sem os comentários (// e /** */): o que conta é o código
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/whatsapp|send_queue|enqueue/i.test(codigo), false);
  // a única RPC é a rodada (o log vai por logEdgeError)
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_explicar_rodar"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada explicar (0d2) roda depois da rodada do cliente e antes da rodada comunicar, com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const cliente = fonte.indexOf("agendaClienteVigia = await vigiarClienteDaAgenda(db, new Date());");
  const explicar = fonte.indexOf("agendaExplicar = await explicarDaAgenda(db, new Date());");
  const comunicar = fonte.indexOf("agendaComunicar = await comunicarDaAgenda(db, agoraDaVigia);");
  const regras = fonte.indexOf("const rules = await runRules(db, settings);");
  assertEquals(cliente > 0 && explicar > cliente && comunicar > explicar && regras > comunicar, true);
  assertEquals(fonte.split("explicarDaAgenda(").length - 1, 1, "uma chamada só");
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaExplicar", explicar), comunicar);
  assertStringIncludes(bloco, "try {");
  assertStringIncludes(bloco, "} catch (e) {");
  assertStringIncludes(fonte, "agenda_explicar: agendaExplicar");
  assertStringIncludes(fonte, 'import { explicarDaAgenda } from "./agenda-explicar.ts";');
  assertStringIncludes(fonte, "//   0d2. A rodada explicar (agenda-explicar.ts, Fase 7g P5)");
});
