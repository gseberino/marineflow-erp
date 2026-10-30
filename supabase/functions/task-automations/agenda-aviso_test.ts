// O aviso do gestor da agenda ao dono no motor de 15 min (Agenda de Produção, correção de 29/10, P4).
//
// O que estes testes protegem:
//  1. a ordem das RPCs: agenda_aviso_conferir (o que a fila fez antes) → agenda_aviso_pecas (o dia de BRASÍLIA e a hora) →
//     agenda_aviso_enfileirar (o texto montado, as ações, as perguntas que foram no texto, o mesmo dia e a mesma hora);
//  2. quando o banco diz que não avisa (fora da janela, teto, nada novo, desligado), nada vai à fila nem ao histórico, e o
//     resumo diz o motivo e o que espera a janela abrir;
//  3. o aviso enfileirado entra no histórico do assistente (a marca do sistema + o texto); a recusa do enfileirar (a mesma
//     rodada, a janela que fechou no meio) não entra;
//  4. NUNCA lança: erro de qualquer RPC, a RPC que lança ou o formato estranho viram { erro } e uma linha em app_error_logs
//     (task-automations / agenda:aviso), e o resto do motor segue;
//  5. a rodada de aprontar que falhou no banco (perguntas_erro) não segura o aviso: ele sai sem as perguntas e o erro fica em
//     app_error_logs (warn), nunca calado.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { avisarDonoDaAgenda, type DepsDoAviso } from "./agenda-aviso.ts";

const A1 = "e513491a-ed1b-4636-9185-44294948343f";
const Q1 = "6037294c-834c-48b0-9943-6d41d85453ec";
const PECAS = {
  avisar: true, rodada: "2026-10-29T19:45:00+00:00", dia: "2026-10-29", limite: 2400,
  cabecalho: "Agenda — o que eu mudei sozinho:",
  mudancas: [{ texto: "Publiquei a semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme: Reserva Lenine (OS-00074): qui 05 a ter 10/11, João os 3 dias, Roberto os 3 dias. *desfaz semana* volta como estava.", acao_ids: [A1] }],
  fora: "Ficou de fora: MP (esperando o sinal).", rodape: "*agenda plano* mostra tudo.",
  perguntas: { texto: "Para montar a semana, uma resposta por OS:\n• Lenine (OS-00074): tem peça a comprar?", pergunta_ids: [Q1] },
};

type Resposta = { data: unknown; error: unknown } | "lança";

function mkDb(r: Partial<Record<"agenda_aviso_conferir" | "agenda_aviso_pecas" | "agenda_aviso_enfileirar", Resposta>>) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const db = {
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      const x = (r as Record<string, Resposta | undefined>)[nome];
      if (x === "lança") return Promise.reject(new Error("conexão caiu"));
      if (x) return Promise.resolve(x);
      if (nome === "agenda_aviso_conferir") return Promise.resolve({ data: { enviados: 0, recusados: 0, devolvidas: 0 }, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    from: (t: string) => {
      throw new Error(`o passo não lê tabela direto (${t})`);
    },
  };
  return { db, rpcs, nomes: () => rpcs.map((x) => x.nome) };
}

function deps() {
  const historico: Array<{ texto: string; agora: Date }> = [];
  const d: DepsDoAviso = {
    historico: (_db, texto, agora) => (historico.push({ texto, agora }), Promise.resolve(true)),
  };
  return { d, historico };
}

// qui 29/10/2026 16:45 de Brasília = 19:45 UTC; 22:30 de Brasília = 01:30 UTC do dia seguinte (o dia ainda é 29/10).
const AS_16H45 = new Date("2026-10-29T19:45:00Z");
const AS_22H30 = new Date("2026-10-30T01:30:00Z");

Deno.test("aviso: conferir → peças (dia de Brasília e a hora) → enfileirar com o texto montado; entra no histórico", async () => {
  const { db, rpcs, nomes } = mkDb({
    agenda_aviso_conferir: { data: { enviados: 1, recusados: 0, devolvidas: 0 }, error: null },
    agenda_aviso_pecas: { data: PECAS, error: null },
    agenda_aviso_enfileirar: { data: { enfileirou: true, id: "aviso-1", fila_id: "fila-1", tentativas: 3 }, error: null },
  });
  const { d, historico } = deps();
  const r = await avisarDonoDaAgenda(db, AS_16H45, d);
  assertEquals(nomes(), ["agenda_aviso_conferir", "agenda_aviso_pecas", "agenda_aviso_enfileirar"]);
  assertEquals(rpcs[0].args, { p_agora: "2026-10-29T19:45:00.000Z" });
  assertEquals(rpcs[1].args, { p_hoje: "2026-10-29", p_agora: "2026-10-29T19:45:00.000Z" });
  const e = rpcs[2].args;
  assertEquals(e.p_acao_ids, [A1]);
  assertEquals(e.p_pergunta_ids, [Q1]);
  assertEquals(e.p_com_perguntas, true);
  assertEquals([e.p_hoje, e.p_agora], ["2026-10-29", "2026-10-29T19:45:00.000Z"]);
  const texto = String(e.p_texto);
  assert(texto.startsWith("Agenda — o que eu mudei sozinho:\n• Publiquei a semana de 03 a 06/11"), texto);
  assertStringIncludes(texto, "\nFicou de fora: MP (esperando o sinal).\n*agenda plano* mostra tudo.\n\nPara montar a semana");
  assertEquals(historico.map((h) => h.texto), [texto]);
  assertEquals(r.avisou, true);
  assertEquals(r.conferido, { enviados: 1, recusados: 0, devolvidas: 0 });
  assertEquals(r.aviso, { id: "aviso-1", fila_id: "fila-1", mudancas: 1, perguntas: 1, caracteres: texto.length, cortes: [] });
  assertEquals(r.historico, true);
});

Deno.test("aviso: às 22:30 de Brasília o dia ainda é o de hoje (o banco diz fora da janela: nada sai, o que mudou espera)", async () => {
  const { db, rpcs, nomes } = mkDb({
    agenda_aviso_pecas: { data: { avisar: false, motivo: "fora_da_janela", janela: "janela", pendentes: 2 }, error: null },
  });
  const { d, historico } = deps();
  const r = await avisarDonoDaAgenda(db, AS_22H30, d);
  assertEquals(rpcs[1].args, { p_hoje: "2026-10-29", p_agora: "2026-10-30T01:30:00.000Z" });
  assertEquals(nomes(), ["agenda_aviso_conferir", "agenda_aviso_pecas"]);
  assertEquals(historico, []);
  assertEquals(r, { conferido: { enviados: 0, recusados: 0, devolvidas: 0 }, avisou: false, motivo: "fora_da_janela", pendentes: 2 });
});

Deno.test("aviso: teto, nada novo, desligado — nada vai à fila nem ao histórico", async () => {
  for (const motivo of ["teto", "nada_mudou", "desligado", "modo", "sem_dono"]) {
    const { db, nomes } = mkDb({ agenda_aviso_pecas: { data: { avisar: false, motivo }, error: null } });
    const { d, historico } = deps();
    const r = await avisarDonoDaAgenda(db, AS_16H45, d);
    assertEquals(nomes(), ["agenda_aviso_conferir", "agenda_aviso_pecas"], motivo);
    assertEquals([r.avisou, r.motivo, historico.length], [false, motivo, 0]);
  }
});

Deno.test("aviso: a recusa do enfileirar (a mesma rodada, a janela que fechou no meio) não entra no histórico", async () => {
  for (const motivo of ["ja_existe", "fora_da_janela", "mudou", "recusada"]) {
    const { db } = mkDb({
      agenda_aviso_pecas: { data: PECAS, error: null },
      agenda_aviso_enfileirar: { data: { enfileirou: false, motivo }, error: null },
    });
    const { d, historico } = deps();
    const r = await avisarDonoDaAgenda(db, AS_16H45, d);
    assertEquals([r.avisou, r.motivo, historico.length], [false, motivo, 0]);
  }
});

Deno.test("aviso: a rodada de aprontar que falhou no banco não segura o aviso — sai sem as perguntas e o erro vai a app_error_logs (warn)", async () => {
  const { db, rpcs } = mkDb({
    agenda_aviso_pecas: { data: { ...PECAS, perguntas: null, perguntas_erro: "XX000: falhou o painel" }, error: null },
    agenda_aviso_enfileirar: { data: { enfileirou: true, id: "aviso-1", fila_id: "fila-1" }, error: null },
  });
  const { d } = deps();
  const r = await avisarDonoDaAgenda(db, AS_16H45, d);
  assertEquals(r.avisou, true);
  const e = rpcs.find((x) => x.nome === "agenda_aviso_enfileirar")!.args;
  assertEquals([e.p_pergunta_ids, e.p_com_perguntas], [[], false]);
  assert(!String(e.p_texto).includes("Para montar a semana"), String(e.p_texto));
  const log = rpcs.find((x) => x.nome === "log_app_error")?.args;
  assertEquals([log?.p_context, log?.p_action, log?.p_level], ["task-automations", "agenda:aviso", "warn"]);
  assertStringIncludes(String(log?.p_message), "saiu sem as perguntas (a rodada de aprontar falhou: XX000: falhou o painel)");
});

Deno.test("aviso: nunca lança — erro, RPC que lança ou formato estranho viram { erro } e app_error_logs (agenda:aviso)", async () => {
  const casos: Array<Parameters<typeof mkDb>[0]> = [
    { agenda_aviso_conferir: { data: null, error: { code: "42883", message: "function agenda_aviso_conferir does not exist" } } },
    { agenda_aviso_pecas: "lança" },
    { agenda_aviso_pecas: { data: { avisar: "talvez" }, error: null } },
    { agenda_aviso_pecas: { data: PECAS, error: null }, agenda_aviso_enfileirar: { data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } } },
  ];
  for (const c of casos) {
    const { db, rpcs } = mkDb(c);
    const { d, historico } = deps();
    const r = await avisarDonoDaAgenda(db, AS_16H45, d);
    assert(typeof r.erro === "string" && r.erro.length > 0, JSON.stringify(r));
    assertEquals(historico, []);
    const log = rpcs.find((x) => x.nome === "log_app_error")?.args;
    assertEquals([log?.p_context, log?.p_action, log?.p_level], ["task-automations", "agenda:aviso", "error"], JSON.stringify(c));
    assertStringIncludes(String(log?.p_message), "aviso do gestor da agenda:");
  }
});
