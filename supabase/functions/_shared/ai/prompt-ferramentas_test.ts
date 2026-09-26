// Guarda: o que o prompt ENSINA tem de existir e tem de estar ao alcance do modelo.
//
// O buraco que isto fecha (levantamento de 26/09/2026): 32 ferramentas citadas no prompt
// estavam escondidas pelo perfil de tools. O modelo obedecia o prompt, chamava, e recebia
// "Tool desconhecida" — em 25/09 foi o "me manda o PDF do orçamento". Nada no caminho
// avisava: o prompt mora em prompt.ts, o perfil morava no banco, e ninguém cruzava os dois.
//
// Regras cobradas aqui, sobre o TEXTO que o modelo lê (o prompt montado, não o arquivo):
//   1. todo identificador snake_case do prompt é uma tool de allTools OU está em
//      NAO_SAO_TOOLS (nome de campo, argumento ou valor). Tool renomeada ou removida que
//      continua ensinada quebra aqui.
//   2. toda tool citada está no perfil (PERFIL_OPERACAO), é de risco alto (entra sempre) ou
//      está em SO_PELA_REDE — a lista, documentada, das que ficam de propósito só pela rede.
//   3. SO_PELA_REDE não guarda sobra: tool que saiu do prompt sai de lá também.
// E sobre o que o modelo lê NAS FERRAMENTAS que recebe — description e input_schema das tools
// VISÍVEIS (perfil ∪ risco alto): a regra 2 vale igual (uma descrição que manda "use antes de
// create_purchase_order_from_so" ensina tanto quanto o prompt), e a decisão do dono sobre o que
// não se ensina mais também. A regra 1 não se aplica ali: esquema é feito de nomes de campo.
// E sobre o que as tools visíveis DEVOLVEM — String(t.execute), onde moram as dicas, notas e
// instructions do resultado: a mesma regra 2 e a mesma decisão do dono. Caso real (26/09):
// criar_regra_financeira devolvia "Use criar_categoria_de_despesa antes", e essa estava fora do
// alcance. A regra 1 também não se aplica: código é cheio de nome de coluna. Limite: só o corpo
// do execute é lido — texto montado num helper de outra função não aparece aqui.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/prompt-ferramentas_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildSystemBlocks } from "./prompt.ts";
import { PERFIL_OPERACAO, SO_PELA_REDE } from "./perfil-operacao.ts";
import { allTools } from "./tools/index.ts";
import { STATUS_OS } from "../service-order-status.ts";
import { registryCrudTools } from "./tools/registry-crud.ts";
import { clientTools } from "./tools/clients.ts";

/**
 * Identificadores snake_case que o prompt cita e que NÃO são ferramentas: campos e argumentos
 * de tool, valores de enum, códigos de bloqueio do portão de comunicação. Os status de OS vêm
 * de STATUS_OS (mesma fonte do prompt). Se este teste acusar um nome novo: se for ferramenta,
 * confira a grafia contra allTools; se for campo ou valor, acrescente aqui.
 */
const NAO_SAO_TOOLS = new Set<string>([
  // argumentos e campos de tool
  "action_name", "asset_type", "billing_unit", "client_id", "collection_ids", "custom_message", "delay_minutes",
  "display_name", "due_at", "entity_id", "extra_notes", "fiscal_verb", "force_new", "from_user", "internal_notes",
  "is_deposit", "is_quote", "item_id", "item_position", "lead_time_days", "markup_percent", "message_id",
  "new_description", "opt_out_whatsapp", "payment_conditions", "payment_status", "problem_description", "product_id",
  "product_type", "proposed_start", "quote_request_id", "recurrence_type", "related_entity_id", "related_entity_type",
  "reminder_offsets_minutes", "response_id", "scheduled_at", "service_name", "service_order_id", "skipped_reason",
  "source_excerpt", "step_id", "supplier_id", "supplier_ids", "unit_price", "vessel_id",
  // envio do orçamento ao cliente (formato da send_service_order_link e campos do resultado)
  "pdf_e_link", "nada_enviado", "enviado_para",
  // tabelas citadas para explicar as duas listas da OS
  "service_order_parts", "service_order_services",
  // campos e marcas que as tools DEVOLVEM
  "avisos_estilo", "link_interno", "midia_nao_lida", "needs_choice", "on_order", "status_pagamento", "ultima_compra",
  // códigos do portão de comunicação
  "destinatario_nao_identificado", "fora_de_horario", "preco_a_tecnico",
  // status do orçamento no funil (update_quote_status), que não é status de OS
  "awaiting_deposit",
  ...STATUS_OS,
]);

function textoDoPrompt(): string {
  // Os dois canais: o bloco estável é o mesmo, mas o volátil do WhatsApp tem texto próprio.
  return (["panel", "whatsapp"] as const)
    .map((channel) => buildSystemBlocks({}, { userName: "Teste", userRole: "admin", channel }).map((b) => b.text).join("\n"))
    .join("\n");
}

function identificadoresSnakeCase(texto: string): Set<string> {
  return new Set(texto.match(/\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g) ?? []);
}

const porNome = new Map(allTools.map((t) => [t.name, t]));
const citados = identificadoresSnakeCase(textoDoPrompt());
const toolsCitadas = [...citados].filter((n) => porNome.has(n));

/** O que o modelo recebe no bloco de tools com o perfil ligado (sem nome no pedido). */
const visiveis = allTools.filter((t) => PERFIL_OPERACAO.has(t.name) || t.risk === "high");

/** Texto de uma tool que o modelo lê: a description e o input_schema (com a descrição dos campos). */
const textoDaTool = (t: { description: string; input_schema: unknown }) => `${t.description}\n${JSON.stringify(t.input_schema)}`;

/** Tools citadas no texto de cada tool visível (a própria não conta). */
const citadasNasVisiveis: Array<{ em: string; tool: string }> = visiveis.flatMap((t) =>
  [...identificadoresSnakeCase(textoDaTool(t))]
    .filter((n) => porNome.has(n) && n !== t.name)
    .map((n) => ({ em: t.name, tool: n }))
);

/** O que a tool devolve ao modelo sai do execute: dica, nota, aviso, instruction. */
const textoDoExecute = (t: { execute: unknown }) => String(t.execute);

/** Tools citadas no execute de cada tool visível (a própria não conta — ex.: RPC de mesmo nome). */
const citadasNosExecutes: Array<{ em: string; tool: string }> = visiveis.flatMap((t) =>
  [...identificadoresSnakeCase(textoDoExecute(t))]
    .filter((n) => porNome.has(n) && n !== t.name)
    .map((n) => ({ em: t.name, tool: n }))
);

/** Ao alcance do modelo: no perfil, de risco alto (entra sempre) ou pela rede, de propósito. */
const aoAlcance = (n: string) => PERFIL_OPERACAO.has(n) || porNome.get(n)!.risk === "high" || SO_PELA_REDE.has(n);

// Decisão do dono (26/09): nenhum uso em ~7 semanas (rotina/automação) e o dono não usa OC de
// verdade. As tools continuam existindo; só não são mais ensinadas — nem no prompt, nem na
// descrição de outra tool. Voltar a ensinar é decisão do dono.
const NAO_SE_ENSINA_MAIS = [
  "record_routine", "list_routines", "propose_automation", "confirm_automation", "get_autonomy_report",
  "create_purchase_order_from_so", "create_purchase_order_from_quote",
];

Deno.test("todo nome snake_case do prompt é tool de verdade ou está na lista de campos/valores", () => {
  const desconhecidos = [...citados].filter((n) => !porNome.has(n) && !NAO_SAO_TOOLS.has(n)).sort();
  assertEquals(desconhecidos, [], "o prompt cita nome que não é tool nem campo conhecido (tool renomeada/removida?)");
  // Sanidade: o scanner achou as tools (se a regex quebrar, o teste acima passaria vazio).
  assertEquals(toolsCitadas.length > 100, true, `só ${toolsCitadas.length} tools citadas — o scanner quebrou?`);
});

Deno.test("toda tool que o prompt ensina está no perfil, é de risco alto ou está em SO_PELA_REDE", () => {
  const semAlcance = toolsCitadas.filter((n) => !aoAlcance(n)).sort();
  assertEquals(semAlcance, [], "o prompt ensina e o perfil esconde: ponha no perfil ou, de propósito, em SO_PELA_REDE");
});

Deno.test("toda tool citada na description/input_schema de uma tool VISÍVEL está ao alcance, como no prompt", () => {
  // Sanidade: o scanner acha as citações (se a regex ou o recorte quebrarem, o teste passaria vazio).
  assertEquals(visiveis.length > 100, true, `só ${visiveis.length} tools visíveis — o recorte quebrou?`);
  assertEquals(citadasNasVisiveis.length > 20, true, `só ${citadasNasVisiveis.length} citações — o scanner quebrou?`);
  assertEquals(citadasNasVisiveis.some((c) => c.em === "suggest_suppliers" && c.tool === "search_products"), true);

  const semAlcance = citadasNasVisiveis.filter((c) => !aoAlcance(c.tool)).map((c) => `${c.em} → ${c.tool}`).sort();
  assertEquals(semAlcance, [], "a descrição de uma tool visível ensina outra que o modelo não alcança: tire a citação ou dê alcance");
});

Deno.test("toda tool citada no execute (dica, nota, instruction) de uma tool VISÍVEL está ao alcance, como no prompt", () => {
  // Sanidade: o scanner lê o corpo do execute (se o recorte quebrar, o teste passaria vazio).
  assertEquals(citadasNosExecutes.length > 20, true, `só ${citadasNosExecutes.length} citações — o scanner quebrou?`);
  // O caso que motivou a guarda: a dica de categoria inexistente em criar_regra_financeira.
  assertEquals(citadasNosExecutes.some((c) => c.em === "criar_regra_financeira" && c.tool === "criar_categoria_de_despesa"), true);

  const semAlcance = citadasNosExecutes.filter((c) => !aoAlcance(c.tool)).map((c) => `${c.em} → ${c.tool}`).sort();
  assertEquals(semAlcance, [], "o resultado de uma tool visível manda usar outra que o modelo não alcança: tire a citação ou dê alcance");
});

Deno.test("SO_PELA_REDE sem sobra: só tool citada (no prompt ou em tool visível), fora do perfil e que não é de risco alto", () => {
  const citadaEmVisivel = new Set([...citadasNasVisiveis, ...citadasNosExecutes].map((c) => c.tool));
  for (const n of SO_PELA_REDE) {
    assertEquals(citados.has(n) || citadaEmVisivel.has(n), true, `${n} ninguém ensina mais — tire de SO_PELA_REDE`);
    assertEquals(PERFIL_OPERACAO.has(n), false, `${n} está no perfil e em SO_PELA_REDE`);
    assertEquals(porNome.get(n)?.risk === "high", false, `${n} é de risco alto e já entra sempre`);
  }
});

Deno.test("decisão do dono (26/09): nem o prompt nem as tools visíveis ensinam rotina/automação ou ordem de compra", () => {
  const texto = textoDoPrompt();
  for (const n of NAO_SE_ENSINA_MAIS) {
    assertEquals(texto.includes(n), false, `${n} voltou ao prompt`);
    const emTools = visiveis.filter((t) => textoDaTool(t).includes(n)).map((t) => t.name);
    assertEquals(emTools, [], `${n} é ensinada na descrição de ${emTools.join(", ")}`);
    const emResultados = visiveis.filter((t) => textoDoExecute(t).includes(n)).map((t) => t.name);
    assertEquals(emResultados, [], `${n} é ensinada no resultado (execute) de ${emResultados.join(", ")}`);
    assertEquals(porNome.has(n), true, `${n} deixou de existir — só o ensino saiu, a tool fica`);
  }
});

Deno.test("update_supplier e update_client aceitam os campos que o prompt manda gravar", () => {
  // O prompt: "grave com update_client/update_supplier (display_name)" e, no opt-out,
  // "marque opt_out_whatsapp=true (update_client/update_supplier)".
  const props = (nome: string) =>
    Object.keys(([...registryCrudTools, ...clientTools].find((t) => t.name === nome)!.input_schema as { properties: object }).properties);
  for (const nome of ["update_supplier", "update_client"]) {
    for (const campo of ["display_name", "opt_out_whatsapp"]) {
      assertEquals(props(nome).includes(campo), true, `${nome} não aceita ${campo}`);
    }
  }
});

Deno.test("update_supplier grava display_name de fato (o patch chega no UPDATE)", async () => {
  const tool = registryCrudTools.find((t) => t.name === "update_supplier")!;
  const updates: Record<string, unknown>[] = [];
  const antes = { id: "s1", name: "Nautimar Comércio Ltda", display_name: null };
  const sb = {
    from: (_t: string) => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: antes, error: null }) }) }),
      update: (patch: Record<string, unknown>) => {
        updates.push(patch);
        return { eq: () => ({ select: () => ({ single: async () => ({ data: { ...antes, ...patch }, error: null }) }) }) };
      },
    }),
  };
  const r = await tool.execute({ supplier_id: "s1", display_name: "Nautimar" }, {
    sb, admin: sb, userId: "u", userRole: "admin", jwt: "", appOrigin: "", settings: {},
  }) as { ok: boolean; alterado: Record<string, { de: unknown; para: unknown }> };
  assertEquals(updates, [{ display_name: "Nautimar" }]);
  assertEquals(r.alterado.display_name, { de: null, para: "Nautimar" });
});
