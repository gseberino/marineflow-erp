// A rodada comunicar da Agenda de Produção no motor de 15 min (Fase 7f, P4 — 08/11/2026).
//
// O que estes testes protegem:
//  1. chama agenda_comunicar_rodar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, a CADA tique (o banco decide o que roda: domingo, os 6 desligados e
//     outra rodada ao mesmo tempo são o normal), e devolve o resumo;
//  2. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations / agenda:comunicar), e o resto do motor segue;
//  3. a função ausente (PGRST202 do PostgREST, 42883 do Postgres: o código publicado antes da migration) é pulada calada — sem 96 linhas de erro por dia;
//  4. os `avisos` que o banco devolve (a mensagem da quinta) vão pelo MESMO caminho do aviso de hoje: o montador _shared/agenda/aviso-do-gestor.ts, o
//     agenda_aviso_enfileirar com p_semana e o mesmo dia, num instante próprio, e o histórico do assistente; sem mudança, com perguntas, sai;
//  5. com tudo em sombra (avisos vazio), nada sai: nenhum enfileirar, nenhuma tabela, nenhum histórico;
//  6. o que o banco recusa (fechamento, teto, ja_existe…) volta no resumo e não entra no histórico; formato estranho não manda nada e registra;
//  7. index.ts chama o passo (0e) depois da rodada do cliente e antes das regras, com o instante da vigia, com try/catch próprio, e o põe no resumo.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { comunicarDaAgenda, type DepsDaComunicacao, RODADA_COMUNICAR_AUSENTE } from "./agenda-comunicar.ts";

const A1 = "e513491a-ed1b-4636-9185-44294948343f";
const Q1 = "6037294c-834c-48b0-9943-6d41d85453ec";
const Q2 = "e452fa40-581c-41af-a037-2adc6297b971";
const PERGUNTAS = "Para a semana que vem preciso de:\n· Você: Quais dias você fica em campo na semana de 16/11?\nPode ser um áudio só, citando o nome do cliente.";
const SEMANA = {
  avisar: true, semana: true, rodada: "2026-11-12T20:00:00+00:00", dia: "2026-11-12", limite: 2400,
  cabecalho: "Agenda — o que eu mudei sozinho:",
  mudancas: [{ texto: "Publiquei a semana de 16 a 20/11. *desfaz semana* volta como estava.", acao_ids: [A1] }],
  fora: null, rodape: "*agenda plano* mostra tudo.", perguntas: { texto: PERGUNTAS, pergunta_ids: [Q1, Q2] }, perguntas_erro: null,
};
const SEMANA_TEXTO = "Agenda — o que eu mudei sozinho:\n• Publiquei a semana de 16 a 20/11. *desfaz semana* volta como estava.\n*agenda plano* mostra tudo.\n\n" + PERGUNTAS;
const SEM_MUDANCA = { ...SEMANA, cabecalho: "Agenda — a semana que vem:", mudancas: [] };
const MODOS = { bloco: "ligado", lote: "ligado", veto: "sombra", previsto: "desligado", convite: "desligado", camadas: "desligado" };

type Resposta = { data: unknown; error: unknown } | "lança";

function mkDb(r: Partial<Record<"agenda_comunicar_rodar" | "agenda_aviso_enfileirar", Resposta>>) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const tabelas: string[] = [];
  const db = {
    from: (tabela: string) => {
      tabelas.push(tabela);
      throw new Error(`tabela inesperada: ${tabela}`);
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      const x = (r as Record<string, Resposta | undefined>)[nome];
      if (x === "lança") return Promise.reject(new Error("conexão caiu"));
      if (x) return Promise.resolve(x);
      if (nome === "agenda_comunicar_rodar") return Promise.resolve({ data: { rodou: false, motivo: "domingo" }, error: null });
      if (nome === "agenda_aviso_enfileirar") {
        return Promise.resolve({ data: { enfileirou: true, id: "aviso-1", fila_id: "fila-1", tentativas: 3, acoes: 1, perguntas: 2 }, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const chamadas = (nome: string) => rpcs.filter((x) => x.nome === nome).map((x) => x.args);
  return { db, rpcs, tabelas, chamadas };
}

function deps(quando = new Date("2026-11-12T20:00:21Z")) {
  const historico: Array<{ texto: string; agora: Date }> = [];
  const d: DepsDaComunicacao = {
    historico: (_db, texto, agora) => (historico.push({ texto, agora }), Promise.resolve(true)),
    agora: () => quando,
  };
  return { d, historico };
}

// qui 12/11/2026 17:00 de Brasília = 20:00 UTC (o 1º tique depois de dono_semana_hora, 16:50)
const QUI_17H = new Date("2026-11-12T20:00:00Z");
// qua 11/11/2026 22:30 de Brasília = 12/11 01:30 UTC: o dia ainda é 11/11
const AS_22H30_BR = new Date("2026-11-12T01:30:00Z");
const rodou = (extra: Record<string, unknown> = {}) => ({
  data: { rodou: true, contagens: { modos: MODOS, quinta: { pulado: true, motivo: "dia" } }, erros: 0, falhas: [], parou_no: null, avisos: [], ...extra },
  error: null,
});

Deno.test("comunicar: chama agenda_comunicar_rodar com o dia de Brasília e a hora, e devolve o resumo da rodada", async () => {
  const { db, chamadas, tabelas } = mkDb({ agenda_comunicar_rodar: rodou() });
  const { d, historico } = deps();
  const r = await comunicarDaAgenda(db, QUI_17H, d);
  assertEquals(chamadas("agenda_comunicar_rodar"), [{ p_hoje: "2026-11-12", p_agora: "2026-11-12T20:00:00.000Z" }]);
  assertEquals(r, { rodou: true, contagens: { modos: MODOS, quinta: { pulado: true, motivo: "dia" } }, erros: 0, falhas: [], parou_no: null });
  assertEquals([tabelas, chamadas("agenda_aviso_enfileirar"), chamadas("log_app_error"), historico], [[], [], [], []]);
});

Deno.test("comunicar: às 22h30 de Brasília o dia ainda é o de hoje (não o de amanhã em UTC)", async () => {
  const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou() });
  await comunicarDaAgenda(db, AS_22H30_BR, deps().d);
  assertEquals(chamadas("agenda_comunicar_rodar")[0].p_hoje, "2026-11-11");
});

Deno.test("comunicar: domingo, os 6 desligados e outra rodada ao mesmo tempo são o normal — sem erro nem log", async () => {
  for (const [data, esperado] of [
    [{ rodou: false, motivo: "domingo" }, { rodou: false, motivo: "domingo" }],
    [{ rodou: false, modos: MODOS }, { rodou: false, modos: MODOS }],
    [{ rodou: false, ocupado: true }, { rodou: false, ocupado: true }],
  ] as const) {
    const { db, chamadas } = mkDb({ agenda_comunicar_rodar: { data, error: null } });
    assertEquals(await comunicarDaAgenda(db, QUI_17H, deps().d), esperado);
    assertEquals([chamadas("log_app_error"), chamadas("agenda_aviso_enfileirar")], [[], []]);
  }
});

Deno.test("comunicar: com tudo em sombra o banco só diz (quinta_diria) e devolve avisos vazio — nada sai, nada é lido, nada vai ao histórico", async () => {
  const contagens = { modos: { ...MODOS, bloco: "sombra", lote: "sombra" }, lote_guardaria: { modo: "sombra" }, quinta: { quinta_diria: { texto: SEMANA_TEXTO } } };
  const { db, chamadas, tabelas } = mkDb({ agenda_comunicar_rodar: rodou({ contagens }) });
  const { d, historico } = deps();
  const r = await comunicarDaAgenda(db, QUI_17H, d);
  assertEquals(r.rodou, true);
  assertEquals("avisos" in r, false);
  assertEquals([chamadas("agenda_aviso_enfileirar"), tabelas, historico, chamadas("log_app_error")], [[], [], [], []]);
});

Deno.test("comunicar: a mensagem da quinta vai pelo caminho do aviso — montador, agenda_aviso_enfileirar com p_semana num instante próprio, histórico", async () => {
  const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou({ avisos: [SEMANA] }) });
  const { d, historico } = deps();
  const r = await comunicarDaAgenda(db, QUI_17H, d);
  assertEquals(chamadas("agenda_aviso_enfileirar"), [{
    p_texto: SEMANA_TEXTO, p_acao_ids: [A1], p_pergunta_ids: [Q1, Q2], p_com_perguntas: true, p_hoje: "2026-11-12",
    p_agora: "2026-11-12T20:00:21.000Z", p_semana: true,
  }]);
  assertEquals(r.avisos, [{ enfileirou: true, id: "aviso-1", fila_id: "fila-1", mudancas: 1, perguntas: 2, caracteres: SEMANA_TEXTO.length, cortes: [], historico: true }]);
  assertEquals(historico, [{ texto: SEMANA_TEXTO, agora: new Date("2026-11-12T20:00:21Z") }]);
  assert(chamadas("agenda_aviso_enfileirar")[0].p_agora !== chamadas("agenda_comunicar_rodar")[0].p_agora, "a rodada do aviso é única por instante: o enfileirar usa o seu");
});

Deno.test("comunicar: sem mudança, com perguntas, a mensagem da semana sai (nenhuma ação conta)", async () => {
  const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou({ avisos: [SEM_MUDANCA] }) });
  const r = await comunicarDaAgenda(db, QUI_17H, deps().d);
  const e = chamadas("agenda_aviso_enfileirar")[0];
  assertEquals([e.p_acao_ids, e.p_pergunta_ids, e.p_semana], [[], [Q1, Q2], true]);
  assertStringIncludes(String(e.p_texto), "Agenda — a semana que vem:\n*agenda plano* mostra tudo.\n\nPara a semana que vem preciso de:");
  assertEquals(r.avisos?.[0].enfileirou, true);
});

Deno.test("comunicar: o que o banco recusa volta no resumo e não entra no histórico", async () => {
  for (const motivo of ["fechamento", "teto", "fora_da_janela", "ja_existe", "modo"]) {
    const { db } = mkDb({ agenda_comunicar_rodar: rodou({ avisos: [SEMANA] }), agenda_aviso_enfileirar: { data: { enfileirou: false, motivo }, error: null } });
    const { d, historico } = deps();
    const r = await comunicarDaAgenda(db, QUI_17H, d);
    assertEquals([r.avisos, historico], [[{ enfileirou: false, motivo }], []]);
  }
});

Deno.test("comunicar: formato que o montador não conhece (ou sem a marca da semana) não manda nada e registra (agenda:comunicar)", async () => {
  for (const ruim of [{ avisar: true }, { ...SEMANA, semana: false }, { ...SEMANA, mudancas: [], perguntas: null }, "x"]) {
    const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou({ avisos: [ruim] }) });
    const r = await comunicarDaAgenda(db, QUI_17H, deps().d);
    assertEquals(r.avisos, [{ enfileirou: false, motivo: "formato" }]);
    assertEquals(chamadas("agenda_aviso_enfileirar"), []);
    assertEquals(chamadas("log_app_error").map((x) => x.p_action), ["agenda:comunicar"]);
  }
});

Deno.test("comunicar: a semana que não cabe nem só com as perguntas não manda nada e registra (warn)", async () => {
  const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou({ avisos: [{ ...SEM_MUDANCA, limite: 20 }] }) });
  const r = await comunicarDaAgenda(db, QUI_17H, deps().d);
  assertEquals(r.avisos, [{ enfileirou: false, motivo: "nada_a_contar" }]);
  assertEquals(chamadas("agenda_aviso_enfileirar"), []);
  assertEquals(chamadas("log_app_error").map((x) => [x.p_action, x.p_level]), [["agenda:comunicar", "warn"]]);
});

Deno.test("comunicar: erro da RPC nunca lança — vira { erro } e app_error_logs (task-automations / agenda:comunicar)", async () => {
  for (const cena of [{ agenda_comunicar_rodar: { data: null, error: { message: "timeout", code: "57014" } } },
                      { agenda_comunicar_rodar: "lança" as const },
                      { agenda_comunicar_rodar: rodou({ avisos: [SEMANA] }), agenda_aviso_enfileirar: { data: null, error: { message: "23514", code: "23514" } } }]) {
    const { db, chamadas } = mkDb(cena as Parameters<typeof mkDb>[0]);
    const r = await comunicarDaAgenda(db, QUI_17H, deps().d);
    assert(typeof r.erro === "string" && r.erro.length > 0, JSON.stringify(r));
    const log = chamadas("log_app_error");
    assertEquals(log.map((x) => [x.p_context, x.p_action]), [["task-automations", "agenda:comunicar"]]);
  }
});

Deno.test("comunicar: sem a função no banco (PGRST202/42883), o passo é pulado calado — sem app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const { db, chamadas } = mkDb({ agenda_comunicar_rodar: { data: null, error: { message: "não existe", code } } });
    assertEquals(await comunicarDaAgenda(db, QUI_17H, deps().d), { pulado: RODADA_COMUNICAR_AUSENTE });
    assertEquals(chamadas("log_app_error"), []);
  }
});

Deno.test("comunicar: o passo que falhou no banco volta em erros/falhas (o banco já registrou) e não gera outra linha aqui", async () => {
  const { db, chamadas } = mkDb({ agenda_comunicar_rodar: rodou({ erros: 1, falhas: [{ passo: "lote_guardaria", sqlstate: "XX000", erro: "x" }] }) });
  const r = await comunicarDaAgenda(db, QUI_17H, deps().d);
  assertEquals([r.erros, r.falhas], [1, [{ passo: "lote_guardaria", sqlstate: "XX000", erro: "x" }]]);
  assertEquals(chamadas("log_app_error"), []);
});

Deno.test("comunicar: o TS não lê o modo nem tabela; as únicas RPCs são a rodada e o enfileirar do aviso (o log vai por logEdgeError)", async () => {
  const fonte = await Deno.readTextFile(new URL("./agenda-comunicar.ts", import.meta.url));
  const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  assertEquals(codigo.includes("agenda_config"), false);
  assertEquals(/\.from\(/.test(codigo), false);
  assertEquals(/send_queue|enqueue/i.test(codigo), false);
  assertEquals([...codigo.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["agenda_aviso_enfileirar", "agenda_comunicar_rodar"]);
  assertStringIncludes(codigo, 'from "../_shared/agenda/aviso-do-gestor.ts"');
  assertStringIncludes(codigo, 'import { historicoDoAviso } from "./agenda-aviso.ts";');
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a rodada comunicar (0e) roda depois da rodada do cliente e antes das regras, com o instante da vigia, com try/catch próprio, e vai ao resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, agoraDaVigia);");
  const aviso = fonte.indexOf("agendaAviso = await avisarDonoDaAgenda(db, agoraDaVigia);");
  const cliente = fonte.indexOf("agendaClienteVigia = await vigiarClienteDaAgenda(db, new Date());");
  const comunicar = fonte.indexOf("agendaComunicar = await comunicarDaAgenda(db, agoraDaVigia);");
  const regras = fonte.indexOf("const rules = await runRules(db, settings);");
  assertEquals(vigia > 0 && aviso > vigia && cliente > aviso && comunicar > cliente && regras > comunicar, true);
  assertEquals(fonte.split("comunicarDaAgenda(").length - 1, 1, "uma chamada só");
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaComunicar", comunicar), regras);
  assertStringIncludes(bloco, "try {");
  assertStringIncludes(bloco, "catch (e)");
  assertStringIncludes(fonte, "agenda_comunicar: agendaComunicar");
  assertStringIncludes(fonte, 'import { comunicarDaAgenda } from "./agenda-comunicar.ts";');
  assertStringIncludes(fonte, "//   0e. A rodada do que se fala (agenda-comunicar.ts, Fase 7f P4)");
});
