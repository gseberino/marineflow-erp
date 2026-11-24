// Pacote 1 do assistente, S1 (24/11/2026): o risco que só o servidor sabe (ToolDef.riscoNoServidor).
//
// Até aqui o risco de uma ação era decidido só pelos ARGUMENTOS que o modelo escolheu (computeRisk). O gancho novo
// deixa a ferramenta ler o banco na hora em que a pendência nasce (quem recebe de fato, o que o texto diz). O que se
// fixa aqui, com uma ferramenta inventada e banco falso:
//   · o gancho só SOBE o risco, nunca rebaixa;
//   · gancho que lança ou responde torto = risco alto, com o motivo "não consegui conferir quem recebe";
//   · o motivo vai para risk_reason e para a última linha do cartão ("🔒 No WhatsApp, pede PIN: …"), só no risco alto;
//   · com motivo, a ação não roda sozinha nem com a chave de autonomia gravada;
//   · pela ferramenta_extra (rede de segurança) o gancho roda pelo mesmo caminho;
//   · sem gancho, ou com gancho sem motivo, a linha gravada da pendência é a de sempre (sem risk_reason).
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/agent-risco-servidor_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarChamadaDeTool, FALHA_AO_CONFERIR_O_RISCO, linhaDoPin } from "./agent.ts";
import { autonomyKey } from "./autonomy-policy.ts";
import { construirFerramentaExtra, NOME_DA_FERRAMENTA_EXTRA } from "./ferramenta-extra.ts";
import { bancoFalso, ctxDe, type Linha } from "./tools/banco-falso-fakes_test.ts";
import type { RiscoNoServidor, RiskLevel, ToolCtx, ToolDef } from "./tools/registry.ts";

const NOME = "ferramenta_inventada_do_teste";

/** Uma ferramenta inventada: o risco declarado, o gancho e um execute que só anota que rodou. */
function inventada(opcoes: {
  risk: RiskLevel;
  computeRisk?: ToolDef["computeRisk"];
  gancho?: (args: Record<string, unknown>, ctx: ToolCtx) => Promise<RiscoNoServidor>;
  gravarSolicitante?: boolean;
}) {
  const rodou: unknown[] = [];
  const vistoPeloGancho: Array<{ args: Record<string, unknown>; userId: string }> = [];
  const tool: ToolDef = {
    name: NOME,
    description: "Ferramenta inventada para o teste do risco visto pelo servidor.",
    input_schema: { type: "object", properties: { texto: { type: "string" } }, required: ["texto"] },
    risk: opcoes.risk,
    ...(opcoes.computeRisk ? { computeRisk: opcoes.computeRisk } : {}),
    ...(opcoes.gravarSolicitante ? { gravarSolicitante: true } : {}),
    ...(opcoes.gancho
      ? {
        riscoNoServidor: (args: Record<string, unknown>, ctx: ToolCtx) => {
          vistoPeloGancho.push({ args, userId: ctx.userId });
          return opcoes.gancho!(args, ctx);
        },
      }
      : {}),
    execute: (args) => {
      rodou.push(args);
      return Promise.resolve({ ok: true });
    },
  };
  return { tool, rodou, vistoPeloGancho };
}

function aVista(tool: ToolDef, db: unknown, extra: Record<string, unknown> = {}) {
  return { toolsByName: { [tool.name]: tool }, alcancaveisPelaRede: {}, toolCtx: ctxDe(db, extra), sessionId: "sessao-s1", channel: "whatsapp" as const };
}
const pendencias = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_pending_actions ?? [];
const chamada = { name: NOME, input: { texto: "oi" } };

Deno.test("S1 gancho: sobe medium para high, grava o motivo em risk_reason e fecha o cartão com a linha do PIN", async () => {
  const b = bancoFalso({});
  const f = inventada({ risk: "medium", gancho: () => Promise.resolve({ risco: "high", motivo: "vai a cliente" }) });
  const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  assertEquals(r.executou, false);
  assertEquals(r.proposal?.risk_level, "high");
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "high", "é o risk_level gravado que cobra o PIN no sim");
  assertEquals(p.risk_reason, "vai a cliente");
  assertEquals(String(p.summary).split("\n").at(-1), "🔒 No WhatsApp, pede PIN: vai a cliente.");
  assertEquals(r.proposal?.summary_markdown, p.summary, "o chat do app mostra o mesmo resumo");
  assertEquals(f.rodou, [], "nada roda antes do sim");
  // O gancho recebe os argumentos da chamada e o contexto de quem pede (nunca um argumento do modelo).
  assertEquals(f.vistoPeloGancho, [{ args: { texto: "oi" }, userId: "dono-1" }]);
  assertEquals(linhaDoPin(["a", "b"]), "🔒 No WhatsApp, pede PIN: a; b.");
});

Deno.test("S1 gancho: o que lança ou responde torto vale risco alto, com o motivo de não ter conseguido conferir", async () => {
  const tortos: Array<[string, () => Promise<RiscoNoServidor>]> = [
    ["lança", () => Promise.reject(new Error("banco fora"))],
    ["lança na hora", () => { throw new Error("explodiu"); }],
    ["devolve nada", () => Promise.resolve(null as unknown as RiscoNoServidor)],
    ["devolve um risco que não existe", () => Promise.resolve({ risco: "altíssimo", motivo: "x" } as unknown as RiscoNoServidor)],
    ["devolve sem risco", () => Promise.resolve({ motivo: "x" } as unknown as RiscoNoServidor)],
  ];
  for (const [nome, gancho] of tortos) {
    const b = bancoFalso({});
    const f = inventada({ risk: "medium", gancho });
    const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
    assertEquals(r.proposal?.risk_level, "high", nome);
    const [p] = pendencias(b);
    assertEquals(p.risk_reason, FALHA_AO_CONFERIR_O_RISCO, nome);
    assertEquals(FALHA_AO_CONFERIR_O_RISCO, "não consegui conferir quem recebe");
    assertStringIncludes(p.summary, "🔒 No WhatsApp, pede PIN: não consegui conferir quem recebe.", nome);
    assertEquals(f.rodou, [], nome);
  }
  // Também numa ferramenta que rodaria direto (risco baixo): a falha do gancho segura a execução.
  const b = bancoFalso({});
  const f = inventada({ risk: "low", gancho: () => Promise.reject(new Error("banco fora")) });
  const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  assertEquals(r.executou, false);
  assertEquals(pendencias(b)[0].risk_level, "high");
  assertEquals(f.rodou, []);
});

Deno.test("S1 gancho: nunca rebaixa o risco declarado nem o calculado pelos argumentos", async () => {
  // Declarado medium, o gancho diz low: continua pedindo o sim, sem a linha do PIN e sem risk_reason.
  const b = bancoFalso({});
  const f = inventada({ risk: "medium", gancho: () => Promise.resolve({ risco: "low", motivo: null }) });
  const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "medium");
  assertEquals("risk_reason" in p, false, "sem motivo, a linha gravada é a de sempre");
  assertEquals(String(p.summary).includes("🔒"), false);

  // Calculado high pelos argumentos, o gancho diz medium: continua high. O motivo que ele deu aparece.
  const b2 = bancoFalso({});
  const f2 = inventada({ risk: "medium", computeRisk: () => "high", gancho: () => Promise.resolve({ risco: "medium", motivo: "o texto cita valor" }) });
  await executarChamadaDeTool(chamada, aVista(f2.tool, b2.db));
  assertEquals(pendencias(b2)[0].risk_level, "high");
  assertEquals(pendencias(b2)[0].risk_reason, "o texto cita valor");
  assertStringIncludes(pendencias(b2)[0].summary, "🔒 No WhatsApp, pede PIN: o texto cita valor.");

  // Declarado low e o gancho também: roda direto, como sempre.
  const b3 = bancoFalso({});
  const f3 = inventada({ risk: "low", gancho: () => Promise.resolve({ risco: "low", motivo: null }) });
  const r3 = await executarChamadaDeTool(chamada, aVista(f3.tool, b3.db));
  assertEquals(r3.executou, true);
  assertEquals(f3.rodou, [{ texto: "oi" }]);
  assertEquals(pendencias(b3), []);
});

Deno.test("S1 gancho: sobe low para medium (pede o sim) sem a linha do PIN; o motivo fica gravado", async () => {
  const b = bancoFalso({});
  const f = inventada({ risk: "low", gancho: () => Promise.resolve({ risco: "medium", motivo: "mexe em contato" }) });
  const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  assertEquals(r.executou, false);
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "medium");
  assertEquals(p.risk_reason, "mexe em contato");
  assertEquals(String(p.summary).includes("🔒"), false, "a linha fala de PIN: só no risco alto");
});

Deno.test("S1 gancho: com motivo, a ação não roda sozinha nem com a chave de autonomia gravada", async () => {
  const liberada = { settings: { [autonomyKey(NOME)]: "auto" } };
  // Controle: sem motivo, a chave 'auto' faz a ação de risco médio rodar direto (é o que a autonomia já fazia).
  const b = bancoFalso({});
  const f = inventada({ risk: "medium", gancho: () => Promise.resolve({ risco: "medium", motivo: null }) });
  const r = await executarChamadaDeTool(chamada, aVista(f.tool, b.db, liberada));
  assertEquals(r.executou, true);
  assertEquals(pendencias(b), []);

  // Com motivo (aqui o gancho subiu para alto), a mesma chave não vale: nasce a pendência com PIN.
  const b2 = bancoFalso({});
  const f2 = inventada({ risk: "medium", gancho: () => Promise.resolve({ risco: "high", motivo: "vai a cliente" }) });
  const r2 = await executarChamadaDeTool(chamada, aVista(f2.tool, b2.db, liberada));
  assertEquals(r2.executou, false);
  assertEquals(f2.rodou, []);
  assertEquals(pendencias(b2)[0].risk_level, "high");

  // E a falha do gancho também trava a autonomia.
  const b3 = bancoFalso({});
  const f3 = inventada({ risk: "medium", gancho: () => Promise.reject(new Error("banco fora")) });
  const r3 = await executarChamadaDeTool(chamada, aVista(f3.tool, b3.db, liberada));
  assertEquals(r3.executou, false);
  assertEquals(f3.rodou, []);
});

Deno.test("S1 gancho: pela ferramenta_extra roda pelo mesmo caminho; com argumentos inválidos nem é chamado", async () => {
  const b = bancoFalso({});
  const f = inventada({ risk: "medium", gancho: () => Promise.resolve({ risco: "high", motivo: "vai a cliente" }) });
  const extra = construirFerramentaExtra([NOME]);
  const amb = {
    toolsByName: { [extra.name]: extra }, alcancaveisPelaRede: { [NOME]: f.tool }, toolCtx: ctxDe(b.db), sessionId: "sessao-s1", channel: "whatsapp" as const,
  };
  const r = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: NOME, argumentos: { texto: "oi" } } }, amb);
  assertEquals(r.proposal?.risk_level, "high");
  const [p] = pendencias(b);
  assertEquals(p.action_name, NOME, "o sim executa a ferramenta de verdade");
  assertEquals(p.risk_reason, "vai a cliente");
  assertStringIncludes(p.summary, "🔒 No WhatsApp, pede PIN: vai a cliente.");

  // Argumentos que não passam no esquema: nada roda e o gancho não lê nada.
  const antes = f.vistoPeloGancho.length;
  const invalida = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: NOME, argumentos: {} } }, amb);
  // deno-lint-ignore no-explicit-any
  assertStringIncludes(String((invalida.toolResult as any).error), "Argumentos inválidos");
  assertEquals(f.vistoPeloGancho.length, antes);
  assertEquals(pendencias(b).length, 1);
});

Deno.test("S1 gancho: a linha do PIN é a última do cartão, depois de 'Pedido por'", async () => {
  const b = bancoFalso({ app_users: [{ id: "dono-1", full_name: "Dono Inventado" }] });
  const f = inventada({ risk: "medium", gravarSolicitante: true, gancho: () => Promise.resolve({ risco: "high", motivo: "vai a cliente; o texto cita valor" }) });
  await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  const linhas = String(pendencias(b)[0].summary).split("\n");
  assertEquals(linhas.at(-2), "Pedido por: *Dono Inventado* (Administrador)");
  assertEquals(linhas.at(-1), "🔒 No WhatsApp, pede PIN: vai a cliente; o texto cita valor.");
  assertEquals(pendencias(b)[0].risk_reason, "vai a cliente; o texto cita valor");
});

Deno.test("S1 gancho: ferramenta sem gancho grava a pendência como sempre (sem risk_reason, sem a linha)", async () => {
  const b = bancoFalso({});
  const f = inventada({ risk: "high" });
  await executarChamadaDeTool(chamada, aVista(f.tool, b.db));
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "high");
  assert(!("risk_reason" in p));
  assertEquals(String(p.summary).includes("🔒"), false);
});
