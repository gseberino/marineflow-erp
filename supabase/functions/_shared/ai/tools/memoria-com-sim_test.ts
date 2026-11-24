// Pacote 1 do assistente, S4 (24/11/2026): a memória só passa a valer com o "sim" do dono.
//   · remember_note      — a nota global entra no texto de TODO turno: pede o "sim", o cartão mostra o texto inteiro, e
//                          só então nasce verificada (verified_by e verified_at de quem deu o "sim");
//   · review_entity_note — aprovar pede o "sim" mesmo com a ferramenta à vista; rejeitar executa direto.
// A leitura das notas (ai-agent/index.ts) não muda: continua lendo só as 'verified'.
// Banco falso em memória; dados inventados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/tools/memoria-com-sim_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bancoFalso, ctxDe, type Linha } from "./banco-falso-fakes_test.ts";
import { memoryTools, resumirNotaGlobal } from "./memory.ts";
import { entityMemoryTools, riscoDeRevisarNota } from "./entity-memory.ts";
import { buildPendingSummary, executarChamadaDeTool, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import type { ToolDef } from "./registry.ts";

const lembrar = memoryTools.find((t) => t.name === "remember_note")!;
const revisar = entityMemoryTools.find((t) => t.name === "review_entity_note")!;

/** O ambiente de uma chamada com a ferramenta À VISTA (no perfil): vale o risco que ela declara ou calcula. */
function aVista(tool: ToolDef, db: unknown) {
  return { toolsByName: { [tool.name]: tool }, alcancaveisPelaRede: {}, toolCtx: ctxDe(db), sessionId: "sessao-s4", channel: "whatsapp" as const };
}
const pendencias = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_pending_actions ?? [];
const notas = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_memory_notes ?? [];

// Mais de 60 caracteres (o título gravado corta em 60) e com quebra de linha: o cartão não pode cortar nada.
const REGRA = "Nunca ofereça desconto acima de 10% sem falar comigo antes.\nPara cliente de marina parceira, o frete de peça é por nossa conta " +
  "e a visita de diagnóstico não é cobrada quando o serviço é aprovado.";

// ─── remember_note ──────────────────────────────────────────────────────────────────────────────

Deno.test("S4 nota global: a ferramenta declara risco medium (pede o sim) e tem título em português", () => {
  assertEquals(lembrar.risk, "medium");
  assertEquals(lembrar.computeRisk, undefined, "sem atalho por argumento: toda nota global pede o sim");
  assertEquals(tituloDaAcao("remember_note"), "Guardar nota na memória");
});

Deno.test("S4 nota global: o cartão mostra o texto INTEIRO da regra, sem corte, e o assunto", async () => {
  assert(REGRA.length > 150);
  const cartao = resumirNotaGlobal({ content: `  ${REGRA}  `, category: "precos" });
  assertEquals(cartao, `Guardar como regra que vale em TODA conversa:\n"${REGRA}"\nAssunto: precos`);
  // Uma regra comprida (a memória aceita qualquer tamanho): inteira no cartão.
  const comprida = "regra ".repeat(800).trim();
  assertStringIncludes(resumirNotaGlobal({ content: comprida, category: "geral" }), `"${comprida}"`);
  // Sem assunto, "geral" (o mesmo que a execução grava).
  assertEquals(resumirNotaGlobal({ content: "Atender primeiro quem está na água." }),
    'Guardar como regra que vale em TODA conversa:\n"Atender primeiro quem está na água."\nAssunto: geral');
  // Pelo caminho do agente é o mesmo texto; nunca lança com argumento torto.
  assertEquals(await buildPendingSummary({}, "remember_note", { content: REGRA, category: "precos" }), resumirNotaGlobal({ content: REGRA, category: "precos" }));
  for (const estranha of [undefined, null, "texto", 42, []]) assertStringIncludes(resumirNotaGlobal(estranha), "Assunto: geral");
});

Deno.test("S4 nota global: a execução (depois do sim) grava a nota verificada, por quem e quando", async () => {
  const b = bancoFalso({ ai_operator_memory_notes: [] });
  const antes = Date.now();
  // deno-lint-ignore no-explicit-any
  const r = await lembrar.execute({ content: REGRA, category: "precos" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  const [nota] = notas(b);
  assertEquals(nota.id, r.note_id);
  assertEquals(nota.scope, "global");
  assertEquals(nota.topic, "precos");
  assertEquals(nota.body, REGRA, "o texto inteiro");
  assertEquals(nota.title, `${REGRA.slice(0, 57)}...`);
  assertEquals(nota.source, "ai");
  assertEquals(nota.verification_status, "verified", "o sim É a aprovação: a nota nasce verificada");
  assertEquals(nota.verified_by, "dono-1", "quem deu o sim");
  assertEquals(nota.created_by, "dono-1");
  const quando = new Date(nota.verified_at).getTime();
  assert(quando >= antes && quando <= Date.now(), `verified_at fora de agora: ${nota.verified_at}`);
  assertEquals(new Date(nota.verified_at).toISOString(), nota.verified_at, "instante ISO");
});

Deno.test("S4 nota global: pelo agente, à vista, vira pendência medium e a nota NÃO existe antes do sim", async () => {
  const b = bancoFalso({ ai_operator_memory_notes: [] });
  const r = await executarChamadaDeTool({ name: "remember_note", input: { content: REGRA, category: "precos" } }, aVista(lembrar, b.db));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  assertEquals(r.executou, false);
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.action_name, "remember_note");
  assertEquals(p.risk_level, "medium", "só o sim, sem PIN");
  assertEquals(p.title, "Guardar nota na memória");
  assertEquals(p.summary, `Guardar como regra que vale em TODA conversa:\n"${REGRA}"\nAssunto: precos`);
  assertEquals(resumoQueRecusa("remember_note", p.summary), null);
  assertEquals(notas(b), [], "antes do sim, nenhuma nota: nada entra no texto dos turnos");

  // O sim executa o payload gravado: só então a nota existe, verificada.
  // deno-lint-ignore no-explicit-any
  const feito = await lembrar.execute(p.payload, ctxDe(b.db)) as any;
  assertEquals(feito.ok, true);
  assertEquals(notas(b).map((n) => [n.body, n.verification_status, n.verified_by]), [[REGRA, "verified", "dono-1"]]);
});

Deno.test("S4 nota global: nota vazia é recusa — nem cartão, nem nota", async () => {
  for (const input of [{ content: "   ", category: "geral" }, { category: "geral" }, {}, undefined]) {
    const b = bancoFalso({ ai_operator_memory_notes: [] });
    const r = await executarChamadaDeTool({ name: "remember_note", input }, aVista(lembrar, b.db));
    assertEquals(r.toolResult, { error: "A nota veio vazia: diga o que é para lembrar." }, JSON.stringify(input));
    assertEquals(r.proposal, undefined);
    assertEquals(pendencias(b), []);
    assertEquals(notas(b), []);
    // a execução confere de novo (pendência antiga ou chamada direta)
    assertEquals(await lembrar.execute(input ?? {}, ctxDe(b.db)), { error: "A nota veio vazia: diga o que é para lembrar." });
    assertEquals(notas(b), []);
  }
});

// ─── review_entity_note ─────────────────────────────────────────────────────────────────────────

const candidata = () => ({
  ai_operator_memory_notes: [{ id: "n1", scope: "client", title: "Costuma pedir desconto", body: "Sempre pede 10%.", verification_status: "candidate",
    verified_by: null, verified_at: null, rejected_by: null, rejected_at: null }],
});

Deno.test("S4 revisar nota: aprovar pede o sim; rejeitar é risco baixo; o cálculo é total e nunca lança", () => {
  assertEquals(revisar.risk, "low", "declarado low: premissa da rede de segurança (agent-rede_test.ts, perfil-operacao_test.ts)");
  assertEquals(revisar.computeRisk, riscoDeRevisarNota);
  assertEquals(riscoDeRevisarNota({ note_id: "n1", decision: "approve" }), "medium");
  assertEquals(riscoDeRevisarNota({ note_id: "n1", decision: "reject" }), "low");
  // Decisão torta ou ausente: o risco mais alto do caso (só o "reject" exato segue direto).
  for (const decision of [undefined, null, "", "APPROVE", " approve", "Reject", "reject ", "aprovar", 1, true, ["reject"], { v: "reject" }]) {
    assertEquals(riscoDeRevisarNota({ note_id: "n1", decision }), "medium", JSON.stringify(decision));
  }
  const hostil = new Proxy({}, { get() { throw new Error("leitura que explode"); } });
  for (const estranha of [undefined, null, "reject", 42, [], ["reject"], hostil]) {
    assertEquals(revisar.computeRisk!(estranha), "medium", String(typeof estranha));
  }
});

Deno.test("S4 revisar nota: pelo agente, à vista, APROVAR vira pendência e a nota continua sugerida até o sim", async () => {
  const b = bancoFalso(candidata());
  const r = await executarChamadaDeTool({ name: "review_entity_note", input: { note_id: "n1", decision: "approve" } }, aVista(revisar, b.db));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  assertEquals(r.executou, false);
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.action_name, "review_entity_note");
  assertEquals(p.risk_level, "medium");
  assertEquals(p.title, "Aprovar ou rejeitar anotação da memória");
  assertEquals(p.payload, { note_id: "n1", decision: "approve" });
  assertStringIncludes(p.summary, "- Decisão: aprovar");
  assertEquals(notas(b)[0].verification_status, "candidate", "sem o sim, a nota não entra no contexto");
  assertEquals(b.gravacoes.filter((g) => g.tabela === "ai_operator_memory_notes"), []);

  // O sim executa o payload: aí sim a nota vale, com quem aprovou e quando.
  // deno-lint-ignore no-explicit-any
  const feito = await revisar.execute(p.payload, ctxDe(b.db)) as any;
  assertEquals(feito.ok, true);
  assertEquals(notas(b)[0].verification_status, "verified");
  assertEquals(notas(b)[0].verified_by, "dono-1");
  assert(notas(b)[0].verified_at);
});

Deno.test("S4 revisar nota: pelo agente, à vista, REJEITAR executa direto, sem cartão", async () => {
  const b = bancoFalso(candidata());
  const r = await executarChamadaDeTool({ name: "review_entity_note", input: { note_id: "n1", decision: "reject" } }, aVista(revisar, b.db));
  assertEquals(r.executou, true);
  assertEquals(r.proposal, undefined);
  assertEquals(pendencias(b), []);
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).ok, true, JSON.stringify(r.toolResult));
  assertEquals(notas(b)[0].verification_status, "rejected");
  assertEquals(notas(b)[0].rejected_by, "dono-1");
  assertEquals(notas(b)[0].verified_by, null);
});

Deno.test("S4 revisar nota: decisão que não é approve nem reject é recusa — nem cartão, nem execução", async () => {
  for (const decision of ["APPROVE", "talvez", "", undefined]) {
    const b = bancoFalso(candidata());
    const r = await executarChamadaDeTool({ name: "review_entity_note", input: { note_id: "n1", decision } }, aVista(revisar, b.db));
    assertEquals(r.toolResult, { error: "decision deve ser approve ou reject." }, String(decision));
    assertEquals(r.executou, false);
    assertEquals(pendencias(b), []);
    assertEquals(notas(b)[0].verification_status, "candidate");
  }
  // Argumentos que não são objeto também não derrubam o turno nem aprovam nada.
  const b = bancoFalso(candidata());
  const r = await executarChamadaDeTool({ name: "review_entity_note", input: undefined }, aVista(revisar, b.db));
  assertEquals(r.toolResult, { error: "decision deve ser approve ou reject." });
  assertEquals(notas(b)[0].verification_status, "candidate");
});
