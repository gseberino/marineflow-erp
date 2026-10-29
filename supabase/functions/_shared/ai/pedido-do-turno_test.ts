// O que o SISTEMA diz sobre o turno (aprovação em lote, Fase 1, 29/10/2026): o recibo das gravações que falharam, o
// desfecho real de uma pendência já decidida, a decisão do WhatsApp na conversa (PIN mascarado) e a guarda da reserva
// do Claude Max. Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/pedido-do-turno_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarChamadaDeTool, runAgentLoop, type ToolEvent } from "./agent.ts";
import {
  anexarAoHistoricoDoTurno,
  avisoDoTurnoInterrompido,
  falhasDaAuditoria,
  falhasDosEventos,
  gravarDecisaoNaConversa,
  jobDeixouTrabalho,
  mascararPin,
  nomeQuePodeTerGravado,
  podeGravar,
  reciboDasGravacoes,
  SO_LEEM_SEM_PREFIXO,
  textoDoDesfecho,
  trabalhoNaAuditoria,
} from "./pedido-do-turno.ts";
import { allTools, type ToolDef } from "./tools/index.ts";

Deno.env.set("OPENROUTER_API_KEY", "test-key-not-real");

// ---------- recibo das gravações ----------

Deno.test("recibo: o caso real de 05/08 14:09 — 4 remoções falhadas viram uma linha com (4×), em português", () => {
  const falhas = Array.from({ length: 4 }, () => ({ ferramenta: "remove_service_order_item", erro: "Item não encontrado" }));
  assertEquals(reciboDasGravacoes(falhas), "⚠️ Conferido pelo sistema: 4 tentativas de gravar deram erro.\n- Remover item do orçamento/OS: Item não encontrado (4×)");
  // a mesma ação deu certo numa ida seguinte ao modelo: o recibo diz o fato (pode ser a tentativa de novo ou outro item)
  assertEquals(
    reciboDasGravacoes(falhas.map((f) => ({ ...f, depoisDeuCerto: 6 }))),
    "⚠️ Conferido pelo sistema: 4 tentativas de gravar deram erro.\n- Remover item do orçamento/OS: Item não encontrado (4×) — depois a mesma ação deu certo 6×",
  );
});

Deno.test("recibo: nada falhou = nada a dizer; uma falha no singular; motivo técnico vira 'erro do sistema'", () => {
  assertEquals(reciboDasGravacoes([]), "");
  assertEquals(
    reciboDasGravacoes([{ ferramenta: "create_service", erro: "O serviço \"X\" já está no catálogo. Nada foi cadastrado." }]),
    '⚠️ Conferido pelo sistema: 1 tentativa de gravar deu erro.\n- Cadastrar serviço: O serviço "X" já está no catálogo. Nada foi cadastrado',
  );
  const tecnico = reciboDasGravacoes([{ ferramenta: "create_service", erro: 'violates check constraint "services_billing_unit_check"' }]);
  assertStringIncludes(tecnico, "erro do sistema (já anotado)");
  assert(!tecnico.includes("violates"), tecnico);
});

Deno.test("recibo: mais de 5 motivos diferentes mostram 5 e dizem quantos ficaram de fora", () => {
  const falhas = Array.from({ length: 7 }, (_, i) => ({ ferramenta: "create_service", erro: `motivo ${i}` }));
  const r = reciboDasGravacoes(falhas);
  assertStringIncludes(r, "7 tentativas de gravar deram erro");
  assertStringIncludes(r, "- e mais 2 motivo(s)");
  assertEquals(r.split("\n").length, 1 + 5 + 1);
});

Deno.test("falhasDosEventos: só o que RODOU e falhou; pendência, recusa e leitura ficam de fora; na extra vale a ferramenta chamada", () => {
  const eventos: ToolEvent[] = [
    { name: "remove_service_order_item", args: {}, result: { error: "Item não encontrado" }, executou: true, ferramenta: "remove_service_order_item" },
    { name: "add_service_to_order", args: {}, result: { ok: true }, executou: true, ferramenta: "add_service_to_order" },
    // virou pendência (não rodou): o erro aqui é o da pré-validação, o modelo recebeu e o dono não aprovou nada
    { name: "register_payment", args: {}, result: { error: "Valor acima do saldo" }, executou: false, ferramenta: "register_payment" },
    // leitura que falhou não é gravação
    { name: "search_clients", args: {}, result: { error: "timeout" }, executou: true, ferramenta: "search_clients" },
    // pela ferramenta_extra: o nome que conta é o da ferramenta chamada
    { name: "ferramenta_extra", args: { nome: "create_service" }, result: { error: "já está no catálogo" }, executou: true, ferramenta: "create_service" },
    // evento antigo, sem a marca: não conta (não dá para saber se rodou)
    { name: "create_service", args: {}, result: { error: "x" } },
  ];
  assertEquals(falhasDosEventos(eventos), [
    { ferramenta: "remove_service_order_item", erro: "Item não encontrado" },
    { ferramenta: "create_service", erro: "já está no catálogo" },
  ]);
});

Deno.test("falhasDosEventos: nenhuma falha some; a mesma ação dando certo numa ida SEGUINTE ao modelo vira nota na linha", () => {
  const ev = (ferramenta: string, rodada: number, erro?: string): ToolEvent => ({
    name: ferramenta, args: {}, result: erro ? { error: erro } : { ok: true }, executou: true, ferramenta, rodada,
  });
  // dado real 31/08: "Montar orçamento" sem a embarcação → cadastra a embarcação → monta de novo
  assertEquals(falhasDosEventos([
    ev("create_quote_from_items", 0, "Nenhum ativo encontrado"), ev("create_vessel", 1), ev("create_quote_from_items", 2),
  ]), [{ ferramenta: "create_quote_from_items", erro: "Nenhum ativo encontrado", depoisDeuCerto: 1 }]);
  // revisão de 29/10: o cabo falhou e o disjuntor (OUTRO item) passou depois — a falha do cabo continua no recibo
  assertEquals(falhasDosEventos([ev("add_service_order_item", 0, "Produto não encontrado"), ev("add_service_order_item", 2)]).length, 1);
  // seis remoções na MESMA resposta, a 2ª falhou: as outras passarem na mesma rodada não entram na nota
  assertEquals(falhasDosEventos([
    ev("remove_service_order_item", 0), ev("remove_service_order_item", 0, "Item não encontrado"),
    ev("remove_service_order_item", 0), ev("remove_service_order_item", 0),
  ]), [{ ferramenta: "remove_service_order_item", erro: "Item não encontrado" }]);
  // dado real 05/08 11:09:03: cinco passaram e a última falhou — nada depois
  assertEquals(falhasDosEventos([...Array.from({ length: 5 }, () => ev("remove_service_order_item", 0)), ev("remove_service_order_item", 1, "Item não encontrado")]),
    [{ ferramenta: "remove_service_order_item", erro: "Item não encontrado" }]);
});

Deno.test("podeGravar: leitura pelo nome e as que só leem sem prefixo ficam de fora; o resto conta (na dúvida, conta)", () => {
  for (const n of ["search_clients", "get_service_order", "list_services", "agenda_ver", "analise_do_negocio", "preview_fiscal_service_note", "present_options"]) {
    assertEquals(podeGravar(n), false, n);
  }
  for (const n of ["create_service", "add_service_order_item", "remove_service_order_item", "os_registrar_andamento", "record_quote_response", "link_contact_to_entity", "atualizar_extrato", "interpret_customer_reply"]) {
    assertEquals(podeGravar(n), true, n);
  }
});

Deno.test("as que só leem sem prefixo existem, são de risco baixo e não têm prefixo de leitura (senão a lista estaria sobrando)", () => {
  const porNome = new Map(allTools.map((t) => [t.name, t]));
  const problemas: string[] = [];
  for (const n of SO_LEEM_SEM_PREFIXO) {
    const t = porNome.get(n);
    if (!t) problemas.push(`${n}: não existe`);
    else if (t.risk !== "low" || t.computeRisk) problemas.push(`${n}: não é de risco baixo`);
    else if (/\.(insert|update|upsert|delete)\(/.test(t.execute.toString())) problemas.push(`${n}: grava no execute`);
  }
  assertEquals(problemas, []);
});

Deno.test("falhasDaAuditoria (Max, sem rodada): 1,5 s ou mais entre as chamadas é outra ida ao modelo — vira a nota 'depois deu certo'", async () => {
  const linha = (ferramenta: string, segundos: number, erro?: string) => ({
    event_type: `tool:${ferramenta}`, payload: { turno: "job-1", ...(erro ? { erro } : {}) }, created_at: new Date(Date.UTC(2026, 9, 20, 15, 46, 0) + segundos * 1000).toISOString(),
  });
  const comLinhas = (linhas: unknown[]) => {
    const q = { select: () => q, eq: () => q, like: () => q, order: () => q, limit: async () => ({ data: linhas, error: null }) };
    return { from: () => q };
  };
  // dado real 20/10 12:46: "Corrigir produto" falhou e, na ida seguinte, passou
  assertEquals(await falhasDaAuditoria(comLinhas([linha("update_product", 0, "Produto não encontrado"), linha("update_product", 4)]), "s1", "job-1"),
    [{ ferramenta: "update_product", erro: "Produto não encontrado", depoisDeuCerto: 1 }]);
  // a mesma ferramenta passando na mesma rajada (0,3 s depois) é outro item do lote: a falha fica
  assertEquals(await falhasDaAuditoria(comLinhas([linha("update_product", 0, "Produto não encontrado"), linha("update_product", 0.3)]), "s1", "job-1"),
    [{ ferramenta: "update_product", erro: "Produto não encontrado" }]);
});

Deno.test("falhasDaAuditoria: lê pelo turno, só as linhas com erro, fora as leituras; leitura que falha devolve []", async () => {
  const filtros: Array<[string, unknown]> = [];
  const linhas = [
    { event_type: "tool:remove_service_order_item", payload: { turno: "job-1", erro: "Item não encontrado" } },
    { event_type: "tool:add_service_to_order", payload: { turno: "job-1" } },
    { event_type: "tool:get_service_order", payload: { turno: "job-1", erro: "timeout" } },
  ];
  const consulta = {
    select: () => consulta,
    eq: (c: string, v: unknown) => (filtros.push([c, v]), consulta),
    like: (c: string, v: unknown) => (filtros.push([c, v]), consulta),
    order: () => consulta,
    limit: async () => ({ data: linhas, error: null }),
  };
  const admin = { from: (t: string) => (assertEquals(t, "ai_operator_audit"), consulta) };
  assertEquals(await falhasDaAuditoria(admin, "s1", "job-1"), [{ ferramenta: "remove_service_order_item", erro: "Item não encontrado" }]);
  assertEquals(filtros, [["session_id", "s1"], ["payload->>turno", "job-1"], ["event_type", "tool:%"]]);
  const quebrado = { from: () => ({ select: () => { throw new Error("rede"); } }) };
  assertEquals(await falhasDaAuditoria(quebrado, "s1", "job-1"), []);
});

Deno.test("anexarAoHistoricoDoTurno: vai para a última fala do assistente (texto, blocos ou bloco novo depois do tool_use)", () => {
  const comTexto = [{ role: "user", content: [{ type: "text", text: "faz" }] }, { role: "assistant", content: [{ type: "text", text: "Feito!" }] }];
  anexarAoHistoricoDoTurno(comTexto, "⚠️ Conferido");
  assertEquals((comTexto[1].content as Array<{ text: string }>)[0].text, "Feito!\n\n⚠️ Conferido");
  const soTool = [{ role: "assistant", content: [{ type: "tool_use", id: "t1" }] }, { role: "user", content: [{ type: "tool_result", tool_use_id: "t1" }] }];
  anexarAoHistoricoDoTurno(soTool as Array<{ role: string; content: unknown }>, "⚠️ Conferido");
  assertEquals((soTool[0].content as Array<{ type: string }>).map((b) => b.type), ["tool_use", "text"]);
  const vazio: Array<{ role: string; content: unknown }> = [];
  anexarAoHistoricoDoTurno(vazio, "x");
  assertEquals(vazio, []);
});

// ---------- turno na auditoria e "executou" no evento ----------

function admimQueGuardaAuditoria() {
  const auditoria: Array<Record<string, any>> = [];
  const admin = {
    from(tabela: string) {
      return {
        select() {
          return { in: async () => ({ data: [], error: null }) };
        },
        insert(linha: Record<string, any>) {
          if (tabela === "ai_operator_audit") auditoria.push(linha);
          return { then: (ok: (v: unknown) => void) => ok({ data: null, error: null }) };
        },
      };
    },
  };
  return { admin, auditoria };
}

const REMOVER: ToolDef = {
  name: "remove_service_order_item",
  description: "teste",
  input_schema: { type: "object", properties: { item_id: { type: "string" } } },
  risk: "low",
  execute: async () => ({ error: "Item não encontrado" }),
};

Deno.test("executarChamadaDeTool: a gravação direta leva o turno e o motivo inteiro à auditoria e diz que rodou", async () => {
  const { admin, auditoria } = admimQueGuardaAuditoria();
  const r = await executarChamadaDeTool({ name: REMOVER.name, input: { item_id: "i1" } }, {
    toolsByName: { [REMOVER.name]: REMOVER }, alcancaveisPelaRede: {}, sessionId: "s1", channel: "whatsapp",
    toolCtx: { sb: {}, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} },
    turno: { id: "job-123", inicio: "2026-10-29T12:00:00Z" },
  });
  assertEquals([r.executou, r.ferramenta], [true, "remove_service_order_item"]);
  assertEquals(auditoria.length, 1);
  assertEquals(auditoria[0].event_type, "tool:remove_service_order_item");
  assertEquals(auditoria[0].payload.turno, "job-123");
  assertEquals(auditoria[0].payload.erro, "Item não encontrado");
});

Deno.test("runAgentLoop: os eventos dizem o que rodou, e todas as linhas de auditoria do turno têm o MESMO turno", async () => {
  const { admin, auditoria } = admimQueGuardaAuditoria();
  const respostas = [
    { tool_calls: [{ id: "c1", type: "function", function: { name: REMOVER.name, arguments: "{\"item_id\":\"a\"}" } }, { id: "c2", type: "function", function: { name: REMOVER.name, arguments: "{\"item_id\":\"b\"}" } }] },
    { content: "✅ Feito!" },
  ];
  let i = 0;
  const original = globalThis.fetch;
  globalThis.fetch = () => {
    const m = respostas[Math.min(i++, respostas.length - 1)];
    return Promise.resolve(new Response(JSON.stringify({
      id: "gen", choices: [{ message: { role: "assistant", content: m.content ?? null, ...(m.tool_calls ? { tool_calls: m.tool_calls } : {}) }, finish_reason: m.tool_calls ? "tool_calls" : "stop" }],
      usage: { prompt_tokens: 10, completion_tokens: 5 },
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
  };
  try {
    const r = await runAgentLoop({
      system: [{ type: "text", text: "teste" }], sessionId: "s1", channel: "whatsapp", tools: [REMOVER],
      messages: [{ role: "user", content: [{ type: "text", text: "tira os dois itens" }] }],
      toolCtx: { sb: {}, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} },
    });
    assertEquals(r.toolEvents.map((e) => [e.executou, e.ferramenta]), [[true, REMOVER.name], [true, REMOVER.name]]);
    const turnos = new Set(auditoria.map((a) => a.payload.turno));
    assertEquals(turnos.size, 1);
    assert(/^[0-9a-f-]{36}$/.test(String([...turnos][0])), "um uuid por turno");
    // o modelo disse "✅ Feito!" — o recibo do sistema diz o contrário, e é o que vale
    assertEquals(reciboDasGravacoes(falhasDosEventos(r.toolEvents)).split("\n")[0], "⚠️ Conferido pelo sistema: 2 tentativas de gravar deram erro.");
  } finally {
    globalThis.fetch = original;
  }
});

// ---------- decisão do WhatsApp na conversa ----------

Deno.test("mascararPin: o PIN e qualquer número de 3 a 8 dígitos somem; o resto fica", () => {
  assertEquals(mascararPin("sim 4321"), "sim ••••");
  assertEquals(mascararPin("Sim 123456 mas manda amanhã"), "Sim •••• mas manda amanhã");
  assertEquals(mascararPin("não"), "não");
  assertEquals(mascararPin("sim 12"), "sim 12");
});

Deno.test("gravarDecisaoNaConversa: a resposta do dono (sem PIN) e o recibo, 1 ms depois, em uma gravação", async () => {
  const gravado: unknown[] = [];
  const admin = { from: (t: string) => ({ insert: async (linhas: unknown) => (assertEquals(t, "ai_operator_messages"), gravado.push(linhas), { error: null }) }) };
  const agora = new Date("2026-10-28T21:57:00.000Z");
  await gravarDecisaoNaConversa(admin, { sessionId: "s1", resposta: "sim 4321", texto: "✅ Cadastrar serviço — executado.", agora });
  assertEquals(gravado, [[
    { session_id: "s1", role: "user", content: "sim ••••", source: "whatsapp", created_at: "2026-10-28T21:57:00.000Z" },
    { session_id: "s1", role: "assistant", content: "✅ Cadastrar serviço — executado.", source: "whatsapp", created_at: "2026-10-28T21:57:00.001Z" },
  ]]);
  // texto vazio não grava; erro do banco não derruba
  await gravarDecisaoNaConversa(admin, { sessionId: "s1", resposta: "sim", texto: "  " });
  assertEquals(gravado.length, 1);
  const quebrado = { from: () => ({ insert: async () => ({ error: { message: "falhou" } }) }) };
  await gravarDecisaoNaConversa(quebrado, { sessionId: "s1", resposta: "sim", texto: "ok" });
});

// ---------- desfecho real ----------

Deno.test("textoDoDesfecho: cada fim em português, com a hora do banco; nunca 'já foi rejected'", () => {
  const agora = new Date("2026-10-28T23:00:00Z"); // 20:00 em Brasília
  const base = { title: "Cadastrar serviço" };
  assertEquals(textoDoDesfecho({ ...base, status: "executed", executed_at: "2026-10-28T21:57:00Z" }, agora),
    "Esse pedido já tinha sido decidido: ✅ Cadastrar serviço — executado às 18:57.");
  assertEquals(textoDoDesfecho({ ...base, status: "rejected", rejected_at: "2026-10-27T12:00:00Z" }, agora),
    "Esse pedido já tinha sido decidido: ❌ Cadastrar serviço — cancelado em 27/10 às 09:00. Nada foi feito.");
  assertEquals(textoDoDesfecho({ ...base, status: "expired", expires_at: "2026-10-28T21:54:00Z" }, agora),
    "⏰ Cadastrar serviço — venceu sem resposta às 18:54. Nada foi feito; se ainda quiser, peça de novo.");
  assertStringIncludes(textoDoDesfecho({ ...base, status: "failed", executed_at: "2026-10-28T21:57:00Z", result: { error: "Item não encontrado" } }, agora),
    "— falhou às 18:57: Item não encontrado");
  assertStringIncludes(textoDoDesfecho({ ...base, status: "approved", approved_at: "2026-10-28T21:57:00Z" }, agora), "ainda sem resultado");
  assertEquals(textoDoDesfecho(null), "Esse pedido não existe mais. Nada foi feito agora.");
  for (const status of ["executed", "failed", "rejected", "expired", "approved", "x"]) {
    assert(!/rejected|expired|executed|failed|approved/.test(textoDoDesfecho({ ...base, status }, agora)), status);
  }
});

// ---------- guarda da reserva ----------

Deno.test("guarda da reserva: pendência, fluxo ou ferramenta que grava = não refazer; só leitura ou opções = pode refazer", () => {
  assertEquals(jobDeixouTrabalho({ interrupcao: { proposal: { pending_action_id: "p1" } } }), true);
  assertEquals(jobDeixouTrabalho({ interrupcao: { fluxo: { codigo: "CMP-1" } } }), true);
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["search_clients", "get_service_order", "present_options"] }), false);
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["search_clients", "add_service_to_order"] }), true);
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["ferramenta_extra:list_services"] }), false);
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["ferramenta_extra:create_service"] }), true);
  // registro antigo: a extra sem dizer qual — na dúvida, não refazer
  assertEquals(nomeQuePodeTerGravado("ferramenta_extra"), true);
  assertEquals(jobDeixouTrabalho({ interrupcao: { options: { question: "Qual?" } } }), false);
  // revisão de 29/10: leitura sem prefixo de leitura (a agenda, a análise do negócio) não é trabalho — o dono não fica sem resposta
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["agenda_ver", "analise_do_negocio", "ferramenta_extra:agenda_ver"] }), false);
  // a extra que só pediu o esquema (descrever) não rodou nada
  assertEquals(jobDeixouTrabalho({ ferramentas_usadas: ["ferramenta_extra:descrever:create_service"] }), false);
  assertEquals(jobDeixouTrabalho(null), false);
});

Deno.test("guarda da reserva pela auditoria: pendência ou escrita do turno = trabalho; leitura não; erro de leitura = na dúvida, trabalho", async () => {
  const comLinhas = (linhas: Array<{ event_type: string }>) => {
    const q = { select: () => q, eq: () => q, limit: async () => ({ data: linhas, error: null }) };
    return { from: () => q };
  };
  assertEquals(await trabalhoNaAuditoria(comLinhas([{ event_type: "tool:search_clients" }]), "s1", "job-1"), false);
  assertEquals(await trabalhoNaAuditoria(comLinhas([{ event_type: "pending_action:create_service" }]), "s1", "job-1"), true);
  assertEquals(await trabalhoNaAuditoria(comLinhas([{ event_type: "tool:add_service_to_order" }]), "s1", "job-1"), true);
  assertEquals(await trabalhoNaAuditoria(comLinhas([{ event_type: "fora_do_perfil:list_services" }]), "s1", "job-1"), false);
  assertEquals(await trabalhoNaAuditoria(comLinhas([{ event_type: "tool:agenda_ver" }, { event_type: "tool:analise_do_negocio" }]), "s1", "job-1"), false);
  const comErro = { from: () => { const q = { select: () => q, eq: () => q, limit: async () => ({ data: null, error: { message: "x" } }) }; return q; } };
  assertEquals(await trabalhoNaAuditoria(comErro, "s1", "job-1"), true);
  assertStringIncludes(avisoDoTurnoInterrompido("timeout"), "parou no meio desta resposta (timeout)");
});
