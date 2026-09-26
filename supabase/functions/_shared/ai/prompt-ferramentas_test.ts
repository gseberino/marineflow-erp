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

Deno.test("todo nome snake_case do prompt é tool de verdade ou está na lista de campos/valores", () => {
  const desconhecidos = [...citados].filter((n) => !porNome.has(n) && !NAO_SAO_TOOLS.has(n)).sort();
  assertEquals(desconhecidos, [], "o prompt cita nome que não é tool nem campo conhecido (tool renomeada/removida?)");
  // Sanidade: o scanner achou as tools (se a regex quebrar, o teste acima passaria vazio).
  assertEquals(toolsCitadas.length > 100, true, `só ${toolsCitadas.length} tools citadas — o scanner quebrou?`);
});

Deno.test("toda tool que o prompt ensina está no perfil, é de risco alto ou está em SO_PELA_REDE", () => {
  const semAlcance = toolsCitadas
    .filter((n) => !PERFIL_OPERACAO.has(n) && porNome.get(n)!.risk !== "high" && !SO_PELA_REDE.has(n))
    .sort();
  assertEquals(semAlcance, [], "o prompt ensina e o perfil esconde: ponha no perfil ou, de propósito, em SO_PELA_REDE");
});

Deno.test("SO_PELA_REDE sem sobra: só tool citada no prompt, fora do perfil e que não é de risco alto", () => {
  for (const n of SO_PELA_REDE) {
    assertEquals(citados.has(n), true, `${n} saiu do prompt — tire de SO_PELA_REDE`);
    assertEquals(PERFIL_OPERACAO.has(n), false, `${n} está no perfil e em SO_PELA_REDE`);
    assertEquals(porNome.get(n)?.risk === "high", false, `${n} é de risco alto e já entra sempre`);
  }
});

Deno.test("decisão do dono (26/09): o prompt não ensina rotina/automação nem ordem de compra", () => {
  // Nenhum uso em ~7 semanas (rotina/automação) e o dono não usa OC de verdade. As tools
  // continuam existindo; só não são mais ensinadas. Voltar a ensinar é decisão do dono.
  const texto = textoDoPrompt();
  for (const n of [
    "record_routine", "list_routines", "propose_automation", "confirm_automation", "get_autonomy_report",
    "create_purchase_order_from_so", "create_purchase_order_from_quote",
  ]) {
    assertEquals(texto.includes(n), false, `${n} voltou ao prompt`);
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
