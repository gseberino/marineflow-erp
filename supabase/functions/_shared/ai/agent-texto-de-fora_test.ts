// Pacote 1 do assistente, S6 (24/11/2026): o turno que leu texto de fora, visto pelo executor do agente.
//
// A regra pura e as listas estão em texto-de-fora_test.ts. Aqui se fixa o que o dono vê e o que roda:
//   · sem leitura de fora no turno, nada muda: o cadastro de fornecedor continua rodando direto;
//   · depois da leitura, cadastro, contato e preço viram cartão com o "sim", com o motivo na última linha e em risk_reason;
//   · a memória vira cartão com PIN, com a linha "🔒 No WhatsApp, pede PIN: este turno leu texto de fora (…)";
//   · com o motivo, a chave de autonomia ai_autonomy_<nome> = 'auto' não vale (a mesma regra do S1);
//   · quem liga a marca é a leitura que RODOU sem erro; pedir só a descrição pela ferramenta_extra não liga;
//   · no laço, a marca vale até o fim do turno, pega a escrita disparada junto com a leitura (lado seguro) e o turno do
//     vigia (🤖) já começa marcado.
// Ferramentas de verdade nas escritas, banco falso em memória, dados inventados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/agent-texto-de-fora_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarChamadaDeTool, runAgentLoop } from "./agent.ts";
import { autonomyKey, NEVER_AUTONOMOUS } from "./autonomy-policy.ts";
import { construirFerramentaExtra, NOME_DA_FERRAMENTA_EXTRA } from "./ferramenta-extra.ts";
import { LEITURAS_DE_TEXTO_DE_FORA, LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA, MOTIVO_DO_TEXTO_DE_FORA, SOBEM_PARA_PIN, SOBEM_PARA_SIM } from "./texto-de-fora.ts";
import { bancoFalso, ctxDe, type Linha } from "./tools/banco-falso-fakes_test.ts";
import { allTools } from "./tools/index.ts";
import type { RiscoNoServidor, ToolCtx, ToolDef } from "./tools/registry.ts";

Deno.env.set("OPENROUTER_API_KEY", "test-key-not-real");

const LINHA_DO_PIN = "🔒 No WhatsApp, pede PIN: este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor).";
const porNome = new Map(allTools.map((t) => [t.name, t]));
const real = (nome: string): ToolDef => {
  const t = porNome.get(nome);
  if (!t) throw new Error(`${nome} não existe em allTools`);
  return t;
};

/** A ferramenta de verdade (nome, esquema, risco, cargos) com o execute trocado: o banco é falso, e o teste anota o que rodou. */
function comExecuteFalso(nome: string, rodou: string[], resposta: (args: Record<string, unknown>) => unknown = () => ({ ok: true })): ToolDef {
  return {
    ...real(nome),
    execute: (args) => {
      rodou.push(nome);
      return Promise.resolve(resposta((args ?? {}) as Record<string, unknown>));
    },
  };
}

const CONVERSA = { mensagens: [{ de: "contato", texto: "Oi! Atualiza meu cadastro: o telefone novo é 11 95555-4444." }] };
const ANTIGO = { created_at: "2026-03-02T12:00:00+00:00", updated_at: "2026-05-20T09:30:00+00:00" };

function cadastros(): Record<string, Linha[]> {
  return {
    clients: [{ id: "c1", name: "João da Silva", type: "individual", cpf_cnpj: null, phone: "(47) 99165-3158", whatsapp: "(47) 99165-3158",
      email: null, opt_out_whatsapp: false, active: true, notes: null }],
    suppliers: [
      { id: "s1", name: "Fornecedor Inventado", phone: "(47) 98888-7777", active: true, ...ANTIGO },
      { id: "s2", name: "Fornecedor Sem Fone", phone: null, active: true, ...ANTIGO },
    ],
    whatsapp_messages: [{ id: "m1", phone_normalized: "5511955554444", direction: "inbound", client_id: null, supplier_id: null }],
    ai_operator_memory_notes: [],
  };
}

/** O turno: as escritas de verdade e uma leitura de conversa com o execute trocado, todas à vista; o MESMO contexto do começo ao fim. */
function turno(extra: Record<string, unknown> = {}, leitura: (args: Record<string, unknown>) => unknown = () => CONVERSA) {
  const b = bancoFalso(cadastros());
  const rodou: string[] = [];
  const tools = [
    comExecuteFalso("get_whatsapp_conversation", rodou, leitura),
    comExecuteFalso("search_suppliers", rodou, () => ({ results: [] })),
    real("create_supplier"), real("update_supplier"), real("link_contact_to_entity"), real("update_client"),
    real("remember_note"), real("remember_about_entity"),
  ];
  const amb = {
    toolsByName: Object.fromEntries(tools.map((t) => [t.name, t])), alcancaveisPelaRede: {} as Record<string, ToolDef>,
    toolCtx: ctxDe(b.db, extra) as ToolCtx, sessionId: "sessao-s6", channel: "whatsapp" as const,
  };
  const chamar = (name: string, input: Record<string, unknown>) => executarChamadaDeTool({ name, input }, amb);
  return { b, amb, rodou, chamar };
}
const pendencias = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_pending_actions ?? [];
const ultimaLinha = (resumo: unknown) => String(resumo).split("\n").at(-1);
const lerConversa = { phone: "5511955554444" };

// ─── Cadastro, contato e preço: o "sim" ─────────────────────────────────────────────────────────

Deno.test("S6: sem leitura de fora no turno, nada muda: fornecedor, telefone e vínculo rodam direto, como antes", async () => {
  const { b, amb, chamar } = turno();
  const cria = await chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" });
  assertEquals(cria.executou, true);
  const troca = await chamar("update_supplier", { supplier_id: "s1", phone: "11 94444-3333" });
  assertEquals(troca.executou, true);
  const liga = await chamar("link_contact_to_entity", { phone: "5511955554444", supplier_id: "s2" });
  assertEquals(liga.executou, true);
  // uma consulta que não lê texto de fora no meio do turno também não muda nada
  await chamar("search_suppliers", { query: "João" });
  const email = await chamar("update_client", { client_id: "c1", email: "joao@x.com" });
  assertEquals(email.executou, true);
  assertEquals(pendencias(b), [], "nenhum cartão");
  assertEquals(amb.toolCtx.leuTextoDeFora, undefined, "a marca não foi ligada");
  assertEquals(b.tabelas.suppliers.length, 3);
});

Deno.test("S6: depois de ler a conversa, cadastrar fornecedor, trocar o telefone dele e ligar o número pedem o sim, com o motivo", async () => {
  const { b, amb, rodou, chamar } = turno();
  const leitura = await chamar("get_whatsapp_conversation", lerConversa);
  assertEquals(leitura.executou, true, "a leitura roda direto");
  assertEquals(rodou, ["get_whatsapp_conversation"]);
  assertEquals(amb.toolCtx.leuTextoDeFora, true, "a leitura que rodou marca o turno");

  // As três da raiz do NOVO-p1-s1-04: rodavam direto, sem cartão.
  const cria = await chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" });
  const troca = await chamar("update_supplier", { supplier_id: "s1", phone: "11 94444-3333" });
  const liga = await chamar("link_contact_to_entity", { phone: "5511955554444", supplier_id: "s2" });
  for (const r of [cria, troca, liga]) {
    assertEquals(r.executou, false);
    assertEquals(r.proposal?.risk_level, "medium");
    // deno-lint-ignore no-explicit-any
    assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  }
  assertEquals(pendencias(b).map((p) => [p.action_name, p.risk_level, p.risk_reason]), [
    ["create_supplier", "medium", MOTIVO_DO_TEXTO_DE_FORA],
    ["update_supplier", "medium", MOTIVO_DO_TEXTO_DE_FORA],
    ["link_contact_to_entity", "medium", MOTIVO_DO_TEXTO_DE_FORA],
  ]);
  for (const p of pendencias(b)) {
    assertEquals(ultimaLinha(p.summary), "Este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor): por isso pede *sim*.");
    assertEquals(String(p.summary).includes("🔒"), false, "risco médio: a linha não fala de PIN");
    assert(String(p.summary).split("\n").length >= 2, "o cartão continua dizendo o que vai ser gravado");
  }
  assertEquals(cria.proposal?.summary_markdown, pendencias(b)[0].summary, "o chat do app mostra o mesmo resumo");
  // Nada foi gravado antes do sim.
  assertEquals(b.tabelas.suppliers.map((s) => [s.id, s.phone]), [["s1", "(47) 98888-7777"], ["s2", null]]);
  assertEquals(b.tabelas.whatsapp_messages[0].supplier_id, null);

  // O sim executa o payload gravado, sem o modelo: o fornecedor nasce como o cartão mostrou.
  // deno-lint-ignore no-explicit-any
  const feito = await real("create_supplier").execute(pendencias(b)[0].payload, amb.toolCtx) as any;
  assertEquals(feito.error, undefined, JSON.stringify(feito));
  assertEquals(b.tabelas.suppliers.length, 3);
});

Deno.test("S6: a troca de contato do cliente, que já pedia o sim (S3), ganha o motivo; o resto do cadastro passa a pedir o sim", async () => {
  const { b, chamar } = turno({ leuTextoDeFora: true });
  await chamar("update_client", { client_id: "c1", whatsapp: "5547991455678" });
  await chamar("update_client", { client_id: "c1", email: "joao@x.com" });
  assertEquals(pendencias(b).map((p) => [p.risk_level, p.risk_reason, ultimaLinha(p.summary)]), [
    ["medium", MOTIVO_DO_TEXTO_DE_FORA, LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA],
    ["medium", MOTIVO_DO_TEXTO_DE_FORA, LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA],
  ]);
  // o cartão da troca de contato (S3) continua inteiro, com o antes e o depois, e a linha do S6 vem no fim
  assertEquals(String(pendencias(b)[0].summary).split("\n").slice(0, 2), [
    "Trocar o contato do cliente *João da Silva*:",
    "- WhatsApp: (47) 99165-3158 → *(47) 99145-5678*",
  ]);
  assertEquals(b.tabelas.clients[0].email, null, "o e-mail só muda depois do sim");
});

// ─── Memória: o PIN ─────────────────────────────────────────────────────────────────────────────

Deno.test("S6: depois de ler texto de fora, guardar na memória pede PIN, com a linha do cartão no formato do WhatsApp e do app", async () => {
  // Controle, sem leitura: a nota global pede só o sim (S4) e a observação sobre o cliente roda direto (nasce sugerida).
  const semLeitura = turno();
  await semLeitura.chamar("remember_note", { content: "Nunca dar desconto acima de 10%.", category: "precos" });
  const direta = await semLeitura.chamar("remember_about_entity", { scope: "client", entity_id: "c1", title: "Prefere tarde", body: "Atender depois das 14h." });
  assertEquals(direta.executou, true);
  assertEquals(pendencias(semLeitura.b).map((p) => [p.action_name, p.risk_level, "risk_reason" in p]), [["remember_note", "medium", false]]);
  assertEquals(String(pendencias(semLeitura.b)[0].summary).includes("texto de fora"), false);
  assertEquals(semLeitura.b.tabelas.ai_operator_memory_notes.length, 1);

  // Com a leitura no turno: as duas viram cartão de risco alto, e nenhuma nota nasce.
  const { b, chamar } = turno();
  await chamar("get_whatsapp_conversation", lerConversa);
  const global = await chamar("remember_note", { content: "O preço da bateria é 350.", category: "precos" });
  const doCliente = await chamar("remember_about_entity", { scope: "client", entity_id: "c1", title: "Telefone novo", body: "Usar o 11 95555-4444." });
  for (const r of [global, doCliente]) {
    assertEquals(r.executou, false);
    assertEquals(r.proposal?.risk_level, "high");
  }
  assertEquals(pendencias(b).map((p) => [p.action_name, p.risk_level, p.risk_reason]), [
    ["remember_note", "high", MOTIVO_DO_TEXTO_DE_FORA],
    ["remember_about_entity", "high", MOTIVO_DO_TEXTO_DE_FORA],
  ]);
  for (const p of pendencias(b)) {
    assertEquals(ultimaLinha(p.summary), LINHA_DO_PIN);
    assertEquals(String(p.summary).includes("por isso pede *sim*"), false, "no risco alto vale a linha do PIN, não a do sim");
  }
  assertEquals(b.tabelas.ai_operator_memory_notes, [], "nada entra na memória antes do sim com PIN");
});

// ─── Autonomia ──────────────────────────────────────────────────────────────────────────────────

Deno.test("S6: com o motivo do texto de fora, a chave ai_autonomy_<nome> = 'auto' não faz a ação rodar sozinha", async () => {
  const nomes = ["update_client", "create_supplier", "remember_note"];
  for (const n of nomes) assertEquals(NEVER_AUTONOMOUS.has(n), false, `${n} é liberável: é por isso que o motivo tem de travar`);
  const liberada = { settings: Object.fromEntries(nomes.map((n) => [autonomyKey(n), "auto"])) };

  // Controle: sem leitura de fora, a chave vale como sempre valeu (a troca de contato e a nota rodam sem cartão).
  const semLeitura = turno(liberada);
  assertEquals((await semLeitura.chamar("update_client", { client_id: "c1", whatsapp: "5547991455678" })).executou, true);
  assertEquals((await semLeitura.chamar("remember_note", { content: "Regra antiga.", category: "geral" })).executou, true);
  assertEquals(pendencias(semLeitura.b), []);

  // Com a leitura no turno, a mesma chave não vale: nasce o cartão, e nada é gravado.
  const { b, chamar } = turno(liberada);
  await chamar("get_whatsapp_conversation", lerConversa);
  const contato = await chamar("update_client", { client_id: "c1", whatsapp: "5547991455678" });
  const fornecedor = await chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" });
  const nota = await chamar("remember_note", { content: "O preço da bateria é 350.", category: "precos" });
  for (const r of [contato, fornecedor, nota]) assertEquals(r.executou, false);
  assertEquals(pendencias(b).map((p) => [p.action_name, p.risk_level]), [["update_client", "medium"], ["create_supplier", "medium"], ["remember_note", "high"]]);
  assertEquals(b.tabelas.clients[0].whatsapp, "(47) 99165-3158");
  assertEquals(b.tabelas.suppliers.length, 2);
  assertEquals(b.tabelas.ai_operator_memory_notes, []);
});

Deno.test("S6: com a marca do turno, NENHUMA ferramenta das duas listas roda direto, nem com todas as chaves de autonomia gravadas", async () => {
  const nomes = [...SOBEM_PARA_SIM, ...SOBEM_PARA_PIN];
  const todasLiberadas = Object.fromEntries(nomes.map((n) => [autonomyKey(n), "auto"]));
  // Cada ferramenta de verdade (nome, esquema, risco, cálculo por argumento), à vista, com o execute trocado e sem argumentos.
  const chamar = async (nome: string, extra: Record<string, unknown>) => {
    const rodou: string[] = [];
    const b = bancoFalso(cadastros());
    const r = await executarChamadaDeTool({ name: nome, input: {} }, {
      toolsByName: { [nome]: comExecuteFalso(nome, rodou) }, alcancaveisPelaRede: {}, sessionId: "sessao-s6", channel: "whatsapp" as const,
      toolCtx: ctxDe(b.db, extra) as ToolCtx,
    });
    return { executou: r.executou === true || rodou.length > 0, cartoes: pendencias(b) };
  };
  const rodavamDireto: string[] = [];
  for (const nome of nomes) {
    // Sem a marca e sem chave de autonomia: o comportamento de sempre (a maioria roda direto; o resto já pedia o sim ou
    // recusa por falta de argumento).
    const antes = await chamar(nome, {});
    if (antes.executou) rodavamDireto.push(nome);
    for (const p of antes.cartoes) assertEquals("risk_reason" in p, false, `${nome}: sem leitura não há motivo`);

    // Com a marca e TODAS as chaves 'auto' gravadas: cartão ou recusa, nunca execução.
    const depois = await chamar(nome, { leuTextoDeFora: true, settings: todasLiberadas });
    assertEquals(depois.executou, false, nome);
    if (antes.executou) assertEquals(depois.cartoes.length, 1, `${nome}: rodava direto e passa a nascer cartão`);
    for (const p of depois.cartoes) {
      assertEquals(p.risk_reason, MOTIVO_DO_TEXTO_DE_FORA, nome);
      if (SOBEM_PARA_PIN.has(nome)) assertEquals(p.risk_level, "high", nome);
      else assert(p.risk_level === "medium" || p.risk_level === "high", nome);
      assertEquals(ultimaLinha(p.summary), p.risk_level === "high" ? LINHA_DO_PIN : LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA, nome);
    }
  }
  // O teste não está vazio: a maior parte das duas listas rodava direto, e as três da raiz do NOVO-p1-s1-04 entre elas.
  assert(rodavamDireto.length >= 15, `só ${rodavamDireto.length} rodavam direto: ${rodavamDireto.join(", ")}`);
  for (const n of ["create_supplier", "update_supplier", "link_contact_to_entity", "create_client", "update_product", "remember_about_entity"]) {
    assert(rodavamDireto.includes(n), `${n} deveria rodar direto sem a marca`);
  }
});

// ─── O que liga a marca ─────────────────────────────────────────────────────────────────────────

Deno.test("S6 marca: só a leitura que rodou sem erro liga; a que falhou, a consulta comum e a própria escrita não ligam", async () => {
  // leitura que devolve erro: nenhum texto de terceiro entrou no turno
  const comErro = turno({}, () => ({ error: "Não achei conversa com esse número." }));
  await comErro.chamar("get_whatsapp_conversation", lerConversa);
  assertEquals(comErro.amb.toolCtx.leuTextoDeFora, undefined);
  assertEquals((await comErro.chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" })).executou, true);

  // leitura que lança: o executor devolve o erro, e a marca não liga
  const queLanca = turno({}, () => { throw new Error("banco fora"); });
  const r = await queLanca.chamar("get_whatsapp_conversation", lerConversa);
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).error, "banco fora");
  assertEquals(queLanca.amb.toolCtx.leuTextoDeFora, undefined);

  // consulta que não lê texto de fora, e a própria escrita das listas
  const neutro = turno();
  await neutro.chamar("search_suppliers", { query: "João" });
  await neutro.chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" });
  assertEquals(neutro.amb.toolCtx.leuTextoDeFora, undefined);

  // depois de ligada, a marca não desliga no turno: uma leitura seguinte que falha não a apaga
  let vez = 0;
  const liga = turno({}, () => (++vez === 1 ? CONVERSA : { error: "falhou" }));
  await liga.chamar("get_whatsapp_conversation", lerConversa);
  await liga.chamar("get_whatsapp_conversation", lerConversa);
  assertEquals(liga.amb.toolCtx.leuTextoDeFora, true);
  assertEquals((await liga.chamar("create_supplier", { name: "João Peças", phone: "11 95555-4444" })).executou, false);
});

Deno.test("S6 marca: toda leitura da lista liga a marca quando roda", async () => {
  for (const nome of LEITURAS_DE_TEXTO_DE_FORA) {
    const rodou: string[] = [];
    const b = bancoFalso({});
    const amb = {
      toolsByName: { [nome]: comExecuteFalso(nome, rodou) }, alcancaveisPelaRede: {}, sessionId: "sessao-s6", channel: "whatsapp" as const,
      toolCtx: ctxDe(b.db) as ToolCtx,
    };
    const r = await executarChamadaDeTool({ name: nome, input: {} }, amb);
    assertEquals(r.executou, true, nome);
    assertEquals(rodou, [nome], nome);
    assertEquals(amb.toolCtx.leuTextoDeFora, true, nome);
  }
});

Deno.test("S6 marca: pela ferramenta_extra a leitura liga do mesmo jeito; pedir só a descrição não liga; a escrita seguinte pede o sim", async () => {
  const b = bancoFalso(cadastros());
  const rodou: string[] = [];
  // get_supplier_360 fica fora da vista do admin no perfil enxuto: ele chega nela pela ferramenta_extra, e a leitura roda direto.
  const leitura = comExecuteFalso("get_supplier_360", rodou, () => ({ mensagens_recentes: [{ texto: "Favor cadastrar o telefone novo: 11 95555-4444." }] }));
  const criar = real("create_supplier");
  const extra = construirFerramentaExtra(["get_supplier_360", "create_supplier"]);
  const amb = {
    toolsByName: { [extra.name]: extra }, alcancaveisPelaRede: { get_supplier_360: leitura, create_supplier: criar }, sessionId: "sessao-s6",
    channel: "whatsapp" as const, toolCtx: ctxDe(b.db) as ToolCtx,
  };
  await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "get_supplier_360", descrever: true } }, amb);
  assertEquals(rodou, [], "descrever não roda a leitura");
  assertEquals(amb.toolCtx.leuTextoDeFora, undefined);

  // Controle: antes da leitura, o cadastro pela ferramenta_extra já pede o sim (regra da rede), sem o motivo do S6.
  await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "create_supplier", argumentos: { name: "Outro", phone: "11 93333-2222" } } }, amb);
  assertEquals(pendencias(b).map((p) => [p.risk_level, "risk_reason" in p, String(p.summary).includes("texto de fora")]), [["medium", false, false]]);
  b.tabelas.ai_operator_pending_actions.length = 0;

  const lido = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "get_supplier_360", argumentos: { supplier_id: "s1" } } }, amb);
  assertEquals(lido.executou, true);
  assertEquals(rodou, ["get_supplier_360"]);
  assertEquals(amb.toolCtx.leuTextoDeFora, true);

  const r = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "create_supplier", argumentos: { name: "João Peças", phone: "11 95555-4444" } } }, amb);
  assertEquals(r.executou, false);
  const [p] = pendencias(b);
  assertEquals([p.action_name, p.risk_level, p.risk_reason], ["create_supplier", "medium", MOTIVO_DO_TEXTO_DE_FORA]);
  assertEquals(ultimaLinha(p.summary), LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA);
});

// ─── O motivo junto com os outros ───────────────────────────────────────────────────────────────

Deno.test("S6 cartão: no risco alto o motivo entra na linha do PIN, junto do que o servidor já disse; a linha é a última", async () => {
  // Uma ferramenta inventada com o NOME de uma da lista do sim (as listas são por nome): o risco e o gancho são do teste.
  const inventada = (opcoes: { risk: "low" | "medium" | "high"; gancho?: () => Promise<RiscoNoServidor>; gravarSolicitante?: boolean }): ToolDef => ({
    name: "update_supplier", description: "inventada", input_schema: { type: "object", properties: { nota: { type: "string" } } },
    risk: opcoes.risk, execute: () => Promise.resolve({ ok: true }),
    ...(opcoes.gancho ? { riscoNoServidor: opcoes.gancho } : {}), ...(opcoes.gravarSolicitante ? { gravarSolicitante: true } : {}),
  });
  const rodar = async (tool: ToolDef, tabelas: Record<string, Linha[]> = {}) => {
    const b = bancoFalso(tabelas);
    await executarChamadaDeTool({ name: tool.name, input: { nota: "x" } }, {
      toolsByName: { [tool.name]: tool }, alcancaveisPelaRede: {}, sessionId: "sessao-s6", channel: "whatsapp" as const,
      toolCtx: ctxDe(b.db, { leuTextoDeFora: true }) as ToolCtx,
    });
    return pendencias(b)[0];
  };
  // Já era de risco alto por conta própria: continua alto, e o cartão avisa do texto de fora.
  const alta = await rodar(inventada({ risk: "high" }));
  assertEquals([alta.risk_level, alta.risk_reason, ultimaLinha(alta.summary)], ["high", MOTIVO_DO_TEXTO_DE_FORA, LINHA_DO_PIN]);
  // O gancho do S1 subiu para alto e deu o motivo dele: os dois motivos, na ordem em que foram achados.
  const comGancho = await rodar(inventada({ risk: "low", gancho: () => Promise.resolve({ risco: "high", motivo: "vai a cliente" }) }));
  assertEquals(comGancho.risk_reason, `vai a cliente; ${MOTIVO_DO_TEXTO_DE_FORA}`);
  assertEquals(ultimaLinha(comGancho.summary), `🔒 No WhatsApp, pede PIN: vai a cliente; ${MOTIVO_DO_TEXTO_DE_FORA}.`);
  // Risco médio com "Pedido por": a linha do S6 vem depois dela.
  const comAutor = await rodar(inventada({ risk: "low", gravarSolicitante: true }), { app_users: [{ id: "dono-1", full_name: "Dono Inventado" }] });
  assertEquals(String(comAutor.summary).split("\n").slice(-2), ["Pedido por: *Dono Inventado* (Administrador)", LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA]);
});

// ─── No laço do OpenRouter ──────────────────────────────────────────────────────────────────────

type Resp = { status: number; body: unknown };
const USO = { prompt_tokens: 100, completion_tokens: 20, prompt_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 } };
/** O modelo pede as ferramentas dadas, todas na MESMA resposta (formato do OpenRouter). */
function chamaTools(...chamadas: Array<[string, unknown]>): Resp {
  return {
    status: 200,
    body: {
      id: "gen_test",
      choices: [{
        message: { role: "assistant", content: null, tool_calls: chamadas.map(([name, input], i) => ({ id: `toolu_${i + 1}`, type: "function", function: { name, arguments: JSON.stringify(input) } })) },
        finish_reason: "tool_calls",
      }],
      usage: USO,
    },
  };
}
const respondeTexto = (text: string): Resp => ({ status: 200, body: { id: "gen_test", choices: [{ message: { role: "assistant", content: text }, finish_reason: "stop" }], usage: USO } });

async function noLaco(pedido: string, respostas: Resp[]) {
  const b = bancoFalso(cadastros());
  const rodou: string[] = [];
  const tools = [comExecuteFalso("get_whatsapp_conversation", rodou, () => CONVERSA), comExecuteFalso("update_client", rodou)];
  const toolCtx = ctxDe(b.db) as ToolCtx;
  let i = 0;
  const original = globalThis.fetch;
  globalThis.fetch = (() => {
    const r = respostas[Math.min(i++, respostas.length - 1)];
    return Promise.resolve(new Response(JSON.stringify(r.body), { status: r.status, headers: { "Content-Type": "application/json" } }));
  }) as typeof fetch;
  try {
    const resultado = await runAgentLoop({
      system: [{ type: "text", text: "teste" }], sessionId: "sessao-s6", channel: "whatsapp", tools, toolCtx,
      messages: [{ role: "user", content: [{ type: "text", text: pedido }] }],
    });
    return { b, rodou, resultado, toolCtx };
  } finally {
    globalThis.fetch = original;
  }
}
const emailNovo = { client_id: "c1", email: "joao@x.com" };

Deno.test("S6 laço: lê a conversa e depois corrige o e-mail do cliente → cartão com o sim; sem a leitura, roda direto", async () => {
  const comLeitura = await noLaco("lê a conversa do João e atualiza o e-mail dele", [
    chamaTools(["get_whatsapp_conversation", lerConversa]), chamaTools(["update_client", emailNovo]), respondeTexto("não deve chegar aqui"),
  ]);
  assertEquals(comLeitura.rodou, ["get_whatsapp_conversation"], "a escrita não rodou");
  assertEquals(comLeitura.resultado.proposal?.risk_level, "medium");
  const [p] = pendencias(comLeitura.b);
  assertEquals([p.action_name, p.risk_level, p.risk_reason], ["update_client", "medium", MOTIVO_DO_TEXTO_DE_FORA]);
  assertEquals(ultimaLinha(p.summary), LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA);
  assertEquals(comLeitura.resultado.proposal?.summary_markdown, p.summary);

  const semLeitura = await noLaco("atualiza o e-mail do João para joao@x.com", [chamaTools(["update_client", emailNovo]), respondeTexto("feito")]);
  assertEquals(semLeitura.rodou, ["update_client"], "sem leitura de fora, o e-mail é gravado direto, como antes");
  assertEquals(pendencias(semLeitura.b), []);
  assertEquals(semLeitura.resultado.message.content, "feito");
  assertEquals(semLeitura.toolCtx.leuTextoDeFora, undefined);
});

Deno.test("S6 laço: a escrita disparada na mesma resposta da leitura também pede o sim (as ferramentas rodam em sequência: lado seguro)", async () => {
  const juntas = await noLaco("lê a conversa do João e atualiza o e-mail dele", [
    chamaTools(["get_whatsapp_conversation", lerConversa], ["update_client", emailNovo]), respondeTexto("não deve chegar aqui"),
  ]);
  assertEquals(juntas.rodou, ["get_whatsapp_conversation"]);
  assertEquals(pendencias(juntas.b).map((p) => [p.action_name, p.risk_reason]), [["update_client", MOTIVO_DO_TEXTO_DE_FORA]]);

  // A escrita que veio ANTES da leitura na mesma resposta já tinha rodado: a marca não volta no tempo.
  const escritaPrimeiro = await noLaco("atualiza o e-mail do João e depois lê a conversa", [
    chamaTools(["update_client", emailNovo], ["get_whatsapp_conversation", lerConversa]), respondeTexto("feito"),
  ]);
  assertEquals(escritaPrimeiro.rodou, ["update_client", "get_whatsapp_conversation"]);
  assertEquals(pendencias(escritaPrimeiro.b), []);
});

Deno.test("S6 laço: o turno do vigia (🤖) já começa marcado: a primeira escrita de cadastro pede o sim, sem leitura nenhuma", async () => {
  const vigia = await noLaco('🤖 Acompanhamento (pedido seu): João (47 99165-3158) está esperando resposta. Última mensagem dele, há 3h: "meu e-mail novo é joao@x.com".', [
    chamaTools(["update_client", emailNovo]), respondeTexto("não deve chegar aqui"),
  ]);
  assertEquals(vigia.rodou, []);
  assertEquals(vigia.toolCtx.leuTextoDeFora, true);
  assertEquals(pendencias(vigia.b).map((p) => [p.action_name, p.risk_level, p.risk_reason]), [["update_client", "medium", MOTIVO_DO_TEXTO_DE_FORA]]);
});
