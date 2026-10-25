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
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildSystemBlocks } from "./prompt.ts";
import { PERFIL_OPERACAO, SO_PELA_REDE } from "./perfil-operacao.ts";
import { allTools } from "./tools/index.ts";
import { STATUS_OS } from "../service-order-status.ts";
import { registryCrudTools } from "./tools/registry-crud.ts";
import { clientTools } from "./tools/clients.ts";
import { lerComandoDaAgenda } from "../agenda/comandos.ts";

/**
 * Identificadores snake_case que o prompt cita e que NÃO são ferramentas: campos e argumentos
 * de tool, valores de enum, códigos de bloqueio do portão de comunicação. Os status de OS vêm
 * de STATUS_OS (mesma fonte do prompt). Se este teste acusar um nome novo: se for ferramenta,
 * confira a grafia contra allTools; se for campo ou valor, acrescente aqui.
 */
const NAO_SAO_TOOLS = new Set<string>([
  // ferramenta montada por turno (perfil enxuto do admin, 05/10/2026): não está em allTools
  "ferramenta_extra",
  // argumento de schedule_whatsapp_message para contato novo (05/10/2026)
  "contact_name",
  // argumento de send_whatsapp_message (roteiro de responder conversa, 06/10/2026)
  "to_phone",
  // argumentos de acompanhar_conversa (06/10/2026)
  "intervalo_horas", "lembrar_em",
  // operacional (07/10/2026): repetição de tarefa, caixa de sugestões, via e laudo da OS
  "dias_da_semana", "dia_do_mes", "repetir_a_cada", "parar_de_repetir", "todas_de_hoje",
  "situacao_na_via", "customer_visible_report", "initial_findings", "solution_applied",
  // argumento de cadastrar_favorecido (regra "todo pagamento para Fulano é <categoria>", 06/10/2026)
  "categoria_padrao",
  // argumentos de registrar_diaria para vários dias (29/09/2026)
  "data_ate", "fim_de_semana",
  // valor dito para o dia (registrar_diaria) e cadastro de freelancer novo (01/10/2026)
  "valor_diaria",
  // pagamento a freelancer e períodos do extrato (06/10/2026)
  "bolso_do_socio", "em_aberto", "desde_ultimo_pagamento",
  // filtros de list_service_orders: situação do orçamento e ordem por valor (03/10/2026)
  "quote_status", "order_by", "maior_valor",
  // cadastros (07/10/2026): argumentos e campos de resultado de search_clients/create_client
  "incluir_inativos", "ja_cadastrado", "possiveis_duplicados", "confirmar_duplicado",
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
  // financeiro (07/10/2026): argumentos de alterar_anotacao_do_extrato, listar_anotacoes_do_extrato,
  // estornar_pagamento, registrar_contato_de_cobranca, list_pending_collections, alterar_favorecido,
  // create_payable e o período de consultar_freelancer
  "novo_valor", "nova_categoria", "nova_data", "parada_ha_mais_de_dias", "payable_id", "prometeu_em", "prometeu_pagar",
  "chave_pix", "tipo_chave_pix", "due_date", "expense_category", "este_mes",
]);
// fiscal e compras (07/10/2026): argumentos de close_quote_request e receive_purchase_order
NAO_SAO_TOOLS.add("gerar_oc");
NAO_SAO_TOOLS.add("receber_tudo");
// planos de manutenção (07/10/2026): valor do filtro situação de list_maintenance_plans
NAO_SAO_TOOLS.add("vencendo_30");
// agrupar orçamentos (15/10/2026): argumento de agrupar_orcamentos e campos de listar_orcamentos_para_agrupar
NAO_SAO_TOOLS.add("voltar_para_em_elaboracao");
NAO_SAO_TOOLS.add("fora_da_lista");
NAO_SAO_TOOLS.add("impedimento_se_voltar");
// compras (24/10/2026, Agenda de Produção P5): campo do retorno de get_purchase_needs (pedido em OC de
// texto livre da OS, ainda não chegou)
NAO_SAO_TOOLS.add("a_caminho");
// agenda (revisão de 23/10/2026): campos do retorno de list_team_agenda (OS do dia sem técnico) e de
// check_technician_availability (OS de vários dias que cobre o horário proposto)
NAO_SAO_TOOLS.add("os_sem_responsavel");
NAO_SAO_TOOLS.add("os_de_varios_dias_no_horario");
// Agenda de Produção (24/10/2026, Fase 1, P7): valores da situação de material_informar que a seção AGENDA DE
// PRODUÇÃO ensina ("chegou" = na_mao, "compro terça" = vou_comprar; a_caminho já está acima)
NAO_SAO_TOOLS.add("na_mao");
NAO_SAO_TOOLS.add("vou_comprar");
// Agenda de Produção (25/10/2026, Fase 4, P1): argumento de fornecedor_prazo ("a Kamell de SC é a mesma do ES")
NAO_SAO_TOOLS.add("mesmo_que");

/** A conversa dos comprovantes ligada (F2): as linhas dos CMPs só entram no prompt assim. */
const CONVERSA_LIGADA = { comprovante_fluxo: "dono", comprovante_conversa: "on" };

function textoDoPrompt(settings: Record<string, string> = CONVERSA_LIGADA): string {
  // Os dois canais: o bloco estável é o mesmo, mas o volátil do WhatsApp tem texto próprio. Com a
  // conversa dos comprovantes ligada (o padrão aqui), entram também as linhas dos CMPs.
  return (["panel", "whatsapp"] as const)
    .map((channel) => buildSystemBlocks(settings, { userName: "Teste", userRole: "admin", channel }).map((b) => b.text).join("\n"))
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

// Comprovantes (F2, revisão de 11/10/2026): com a conversa desligada, ou em sombra, o assistente é o
// de antes — nenhuma linha sobre CMP (a legenda do cupom ainda chega a ele e ele lança o que o dono pede).
Deno.test("prompt: as linhas dos comprovantes só entram com a conversa ligada", () => {
  for (const settings of [{}, { comprovante_fluxo: "sombra", comprovante_conversa: "on" }, { comprovante_fluxo: "dono", comprovante_conversa: "off" }] as Array<Record<string, string>>) {
    const texto = textoDoPrompt(settings);
    assertEquals(texto.includes("COMPROVANTES (CMP"), false, JSON.stringify(settings));
    assertEquals(texto.includes("fluxo de comprovantes"), false, JSON.stringify(settings));
  }
  const ligada = textoDoPrompt();
  assertEquals(ligada.includes("COMPROVANTES (CMP"), true);
  assertEquals(ligada.includes("*cancelar cmp N*"), true);
  assertEquals(ligada.includes("[image]/[document] do dono é do fluxo de comprovantes"), true);
});

// Agenda de Produção (24/10/2026, Fase 1, P7): a seção que ENSINA as 4 ferramentas da agenda. "Tool registrada não é
// tool ensinada": sem estas linhas o modelo calcula data, grava sem a releitura ou responde "gravei". Cada regra da
// seção é amarrada aqui ao que ela cita de verdade (o enum da ferramenta, a palavra que o comando lê).
const SECAO_AGENDA = "════ AGENDA DE PRODUÇÃO (só o dono) ════";

function secaoDaAgenda(): string {
  const estavel = buildSystemBlocks(CONVERSA_LIGADA, { userName: "Teste", userRole: "admin", channel: "whatsapp" })[0].text;
  const i = estavel.indexOf(SECAO_AGENDA);
  assertEquals(i >= 0, true, "a seção AGENDA DE PRODUÇÃO sumiu do bloco estável");
  const fim = estavel.indexOf("\n════", i + SECAO_AGENDA.length);
  return estavel.slice(i, fim < 0 ? undefined : fim).trim();
}

// Fase 1: 7 linhas (o título + 6). Fase 2 (P6): no máximo 10 a mais (spec-fase2.md §12.2) — entraram 6. Teto 17.
// Fase 3 (P6): no máximo 8 a mais sobre as 13 (spec-fase3.md §9.6) — entraram 5. Teto 21.
Deno.test("agenda de produção: a seção é curta (≤ 21 linhas: custa tokens em toda mensagem) e fica no bloco estável", () => {
  const secao = secaoDaAgenda();
  const linhas = secao.split("\n");
  assertEquals(linhas.length <= 21, true, `a seção tem ${linhas.length} linhas`);
  // Estável = em cache. O volátil muda a cada turno e não pode carregar a seção.
  const volatil = buildSystemBlocks(CONVERSA_LIGADA, { userName: "Teste", userRole: "admin", channel: "whatsapp" })[1].text;
  assertEquals(volatil.includes(SECAO_AGENDA), false);
});

Deno.test("agenda de produção: o dono vai para agenda_ver; my_agenda fica para técnico e financeiro", () => {
  const texto = textoDoPrompt();
  const linhaDaAgenda = texto.split("\n").find((l) => l.includes("\"minha agenda\"") && l.includes("my_agenda"))!;
  assertEquals(!!linhaDaAgenda, true, "a linha de \"minha agenda\" sumiu");
  assertEquals(/\(dono\)[^()]*"o que eu tenho que fazer"[^→]*→ agenda_ver/.test(linhaDaAgenda), true, linhaDaAgenda);
  assertEquals(/\(técnico e financeiro\) "minha agenda"[^→]*→ my_agenda/.test(linhaDaAgenda), true, linhaDaAgenda);
  // check_technician_availability sozinho: my_agenda saiu da vista do admin (d14), ensinar os dois juntos manda o dono
  // para a ferramenta escondida.
  assertEquals(texto.includes("check_technician_availability/my_agenda"), false);
  assertEquals(texto.includes("(use check_technician_availability)"), true);
});

Deno.test("agenda de produção: só agenda_ver dá data; nada é gravado sem *grava*; as fronteiras com as vizinhas", () => {
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "vêm SÓ de agenda_ver: nunca calcule, some dias nem estime");
  assertStringIncludes(secao, "nunca mude número, data ou nome");
  assertStringIncludes(secao, "nunca mande mensagem por conta própria");
  assertStringIncludes(secao, "agenda_ver foco aprontar");
  for (const t of ["os_planejar", "material_informar", "equipe_disponibilidade"]) assertStringIncludes(secao, t);
  assertStringIncludes(secao, "trecho = as palavras dele");
  assertStringIncludes(secao, "aqui não converta para ISO");
  assertStringIncludes(secao, "nunca diz \"gravei\"");
  // Fronteiras: cada vizinha citada por nome (e o nome é tool de verdade, ao alcance — os testes acima cobram).
  for (const t of ["create_task", "schedule_service_order", "get_purchase_needs", "registrar_diaria", "add_service_order_item"]) {
    assertStringIncludes(secao, t);
    assertEquals(porNome.has(t), true, `${t} não é ferramenta`);
  }
  // equipe_disponibilidade (quem VAI vir) × registrar_diaria (o dia que já aconteceu: a falta mexe no pagamento) e
  // material_informar com novo (só avisa a agenda) × add_service_order_item (a peça que entra na OS e na compra).
  assertStringIncludes(secao, "equipe_disponibilidade é quem VAI vir");
  assertStringIncludes(secao, "(\"não veio hoje\", \"faltou ontem\") é registrar_diaria");
  assertStringIncludes(secao, "material_informar com novo só avisa a agenda e não põe a peça na OS nem na compra");
});

Deno.test("agenda de produção: o que a seção ensina existe na ferramenta e no comando", () => {
  const secao = secaoDaAgenda();
  // "foco aprontar" e as situações ditas ("chega dia 3" = a_caminho, "chegou" = na_mao, "compro terça" = vou_comprar)
  // são valores do enum de verdade: renomear lá sem mudar aqui quebra.
  const agendaVer = porNome.get("agenda_ver")!;
  const material = porNome.get("material_informar")!;
  const enumDe = (t: { input_schema: unknown }, campo: string) =>
    ((t.input_schema as { properties: Record<string, { enum?: string[] }> }).properties[campo].enum ?? []);
  assertEquals(enumDe(agendaVer, "foco").includes("aprontar"), true);
  for (const s of ["a_caminho", "na_mao", "vou_comprar"]) {
    assertStringIncludes(secao, ` ${s}`);
    assertEquals(enumDe(material, "situacao").includes(s), true, `${s} não é situação de material_informar`);
  }
  // "Pode voltar" = os_planejar com limpar espera: o valor existe no enum de verdade (sem ele, a espera não tem saída).
  assertStringIncludes(secao, "\"pode voltar\" ou \"tira da espera\" é os_planejar com limpar espera");
  const planejar = porNome.get("os_planejar")!;
  const limpar = (planejar.input_schema as { properties: Record<string, { items?: { enum?: string[] } }> }).properties.limpar;
  assertEquals(limpar?.items?.enum?.includes("espera"), true, "espera não é valor de os_planejar.limpar");
  // A frase que o modelo diz ao "sim" da releitura manda uma palavra que o comando sem IA LÊ (senão o dono manda
  // *grava* e cai de novo no modelo).
  const frase = /"Para gravar, mande só (\*grava\*)\."/.exec(secao);
  assertEquals(!!frase, true, "a frase do sim/ok à releitura sumiu");
  assertEquals(lerComandoDaAgenda(frase![1])?.comando, "gravar");
  // E o "sim"/"ok" que ela responde NÃO é o comando (é por isso que a frase existe).
  for (const s of ["sim", "ok", "grava aí"]) assertEquals(lerComandoDaAgenda(s), null, s);
});

// Agenda de Produção (24/10/2026, Fase 2, P6): a agenda se monta sozinha e o dono pede pela conversa. As 4 ferramentas
// novas chegam pela ferramenta_extra (d14: só agenda_ver à vista), então é o prompt que as ensina — sem estas linhas o
// modelo marca por conta própria, escolhe a opção da decisão pelo dono ou confunde andamento, diária e check-in.
Deno.test("agenda de produção (Fase 2): autonomia, pedidos viram releitura, decisão sem escolher pelo dono, andamento × diária × check-in", () => {
  const secao = secaoDaAgenda();
  // 1. a autonomia e o que mudou: os focos citados existem no enum de agenda_ver
  assertStringIncludes(secao, "A agenda se monta e se ajusta sozinha");
  assertStringIncludes(secao, "você não marca, não move e não publica por conta própria");
  const agendaVer = porNome.get("agenda_ver")!;
  const focos = (agendaVer.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  for (const foco of ["mudancas", "decisoes", "plano"]) {
    assertStringIncludes(secao, `foco ${foco}`);
    assertEquals(focos.includes(foco), true, `${foco} não é foco de agenda_ver`);
  }
  // 2. pedido vira releitura: simular (agenda_propor), marcar num dia (schedule_service_order com quando e trecho, que
  //    existem no esquema dela), montar/tirar de verdade (simular false + agenda_aplicar), publicar (agenda_aplicar)
  assertStringIncludes(secao, "Pedido do dono à agenda vira releitura, nunca fato");
  assertStringIncludes(secao, "é agenda_propor, que só simula");
  assertStringIncludes(secao, "é schedule_service_order com quando = o dia como ele disse e trecho");
  const marcar = porNome.get("schedule_service_order")!.input_schema as { properties: Record<string, unknown> };
  for (const campo of ["quando", "trecho"]) assertEquals(campo in marcar.properties, true, `schedule_service_order sem ${campo}`);
  assertStringIncludes(secao, "agenda_propor com simular false e, em seguida, agenda_aplicar com proposta \"a última\"");
  const propor = porNome.get("agenda_propor")!.input_schema as { properties: Record<string, unknown> };
  assertEquals("simular" in propor.properties, true);
  // 3. decisão: agenda_ver foco decisoes → agenda_aplicar com decisao e opcao; nunca escolher pelo dono
  assertStringIncludes(secao, "agenda_ver foco decisoes para achar o nº e as opções, depois agenda_aplicar com decisao e opcao");
  assertStringIncludes(secao, "Nunca escolha a opção por ele");
  const aplicar = porNome.get("agenda_aplicar")!.input_schema as { properties: Record<string, unknown> };
  for (const campo of ["decisao", "opcao", "proposta"]) assertEquals(campo in aplicar.properties, true, `agenda_aplicar sem ${campo}`);
  // 4. andamento × diária × check-in × concluir: cada vizinha citada por nome (e é ferramenta de verdade)
  assertStringIncludes(secao, "os_registrar_andamento, uma chamada por fato, com trecho e motivo da lista");
  // FASE 3 (P3): concluir e entregar são eventos do andamento (o teste da Fase 3, abaixo, cobra a linha nova).
  assertStringIncludes(secao, "é evento concluiu ou entregou");
  assertStringIncludes(secao, "é registrar_diaria, que já usa a OS do plano");
  assertStringIncludes(secao, "a chegada que o técnico diz é check_in_service_order");
  for (const t of ["agenda_propor", "agenda_aplicar", "agenda_desfazer", "os_registrar_andamento", "check_in_service_order"]) {
    assertEquals(porNome.has(t), true, `${t} não é ferramenta`);
  }
  // 5. desfazer pela ferramenta e as palavras que o dono manda direto: o comando sem IA LÊ cada uma
  assertStringIncludes(secao, "agenda_desfazer com o alvo");
  for (const [palavra, comando] of [["dia feito", "dia"], ["dia nao cliente", "dia"], ["choveu", "choveu"], ["desfaz Nelson", "desfazer"]]) {
    assertEquals(lerComandoDaAgenda(palavra)?.comando, comando, palavra);
  }
  // 6. nunca data fora das ferramentas, e nada de "marquei/publiquei/desfiz" sem o *grava*
  assertStringIncludes(secao, "Nunca diga data, dia livre ou pessoa que não veio de uma ferramenta da agenda");
  assertStringIncludes(secao, "\"marquei\", \"publiquei\" nem \"desfiz\"");
});

// Agenda de Produção (24/10/2026, Fase 3, P3): concluir e entregar voltaram ao assistente pela porta — o andamento com a
// releitura da saída e das cobranças e o *grava* do dono, as palavras *concluiu* e *entreguei*. As 3 linhas que diziam
// "concluir é pela tela" foram reescritas juntas (sem isso o prompt se contradiz): aqui cada uma é amarrada ao que cita.
Deno.test("agenda de produção (Fase 3): concluir e entregar pelo andamento e pelas palavras; update_service_order_status não conclui", () => {
  const estavel = buildSystemBlocks(CONVERSA_LIGADA, { userName: "Teste", userRole: "admin", channel: "whatsapp" })[0].text;
  // 1. a regra geral (fora da seção da agenda): o caminho de concluir e de entregar, e o que não conclui
  assertStringIncludes(estavel, "Concluir e entregar: os_registrar_andamento (concluiu/entregou) com o trecho; o dono confirma com *grava*. update_service_order_status não conclui; cancelar é cancel_service_order.");
  assertEquals(estavel.includes("Concluir é pela tela"), false, "sobrou a regra antiga");
  assertEquals(estavel.includes("concluir continua pela tela"), false, "sobrou a regra antiga");
  // 2. os eventos citados existem no enum da ferramenta
  const andamento = porNome.get("os_registrar_andamento")!.input_schema as { properties: { evento: { enum: string[] } } };
  for (const e of ["concluiu", "entregou"]) assertEquals(andamento.properties.evento.enum.includes(e), true, e);
  // 3. as palavras que o dono manda direto: o comando sem IA LÊ cada uma
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "*concluiu* + nome e *entreguei* + nome o dono manda direto, sem você");
  assertEquals(lerComandoDaAgenda("concluiu Lenine")?.comando, "concluir");
  assertEquals(lerComandoDaAgenda("entreguei Lenine")?.comando, "entregar");
  // 4. o técnico: o check-out continua não concluindo, e o "terminou" do DONO aponta o andamento
  assertStringIncludes(estavel, "check-out NÃO conclui nem fatura a OS");
  assertStringIncludes(estavel, "quando o DONO diz que o serviço terminou, é os_registrar_andamento com evento concluiu");
  // 5. update_service_order_status devolve a instrução (não recusa): o texto dela cita a ferramenta certa
  const status = porNome.get("update_service_order_status")!;
  assertStringIncludes(status.description, "os_registrar_andamento, evento concluiu");
});

// Agenda de Produção (24/10/2026, Fase 3, P6): o acompanhamento — a rotina da equipe é sozinha (o modelo não manda nem
// lança), os focos novos de agenda_ver (cada um existe no enum), a comissão que é só a conta, a resposta à pergunta da
// diária pela decisão (sem escolher pelo dono), as palavras que o dono manda direto (o comando sem IA lê cada uma) e a
// carona ("Aproveitando: …" é da agenda). Nenhuma ferramenta nova (o teto do perfil continua): só o ensino delas.
Deno.test("agenda de produção (Fase 3, P6): a equipe sozinha, os focos ppc/diarias/equipe/marcos/comissao, a diária pela decisão e a carona", () => {
  const secao = secaoDaAgenda();
  // 1. a rotina da equipe e a diária automática não são do modelo
  assertStringIncludes(secao, "Você nunca manda mensagem à equipe nem lança diária por conta própria.");
  // 2. os focos citados existem no enum de agenda_ver
  const agendaVer = porNome.get("agenda_ver")!;
  const focos = (agendaVer.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  for (const foco of ["ppc", "diarias", "equipe", "marcos", "comissao"]) {
    assertStringIncludes(secao, `foco ${foco}`);
    assertEquals(focos.includes(foco), true, `${foco} não é foco de agenda_ver`);
  }
  // 3. a comissão é só a conta, nunca pagamento (o texto do banco diz "nada foi pago"; o modelo repete)
  assertStringIncludes(secao, "diga sempre que é só a conta e que nada foi pago");
  assertStringIncludes(agendaVer.description, "só a conta, nada é pago");
  // 4. a pergunta da diária: a decisão pela agenda_aplicar, sem escolher; fora disso, registrar_diaria
  assertStringIncludes(secao, "agenda_ver foco decisoes e agenda_aplicar com decisao e opcao; nunca escolha a opção");
  // 5. as palavras que o dono manda direto: o comando sem IA LÊ cada uma
  assertEquals(lerComandoDaAgenda("diária Roberto meia")?.comando, "diaria");
  assertEquals(lerComandoDaAgenda("diária Roberto inteira")?.comando, "diaria");
  assertEquals(lerComandoDaAgenda("diária Roberto não")?.comando, "diaria");
  // revisão da Fase 3: a palavra ensinada é *como foi a semana* (sem o jargão "PPC"); *agenda ppc* continua aceita
  assertStringIncludes(secao, "*como foi a semana*");
  assertEquals(secao.includes("*agenda ppc*"), false, "o prompt não ensina *agenda ppc*");
  for (const [palavra, foco] of [["como foi a semana", "ppc"], ["agenda ppc", "ppc"], ["agenda equipe", "equipe"], ["comissão outubro", "comissao"]]) {
    const c = lerComandoDaAgenda(palavra);
    assertEquals(c?.comando === "ver" ? c.foco : null, foco, palavra);
  }
  // 6. a carona: o modelo não a repete nem responde por ele
  assertStringIncludes(secao, "Se a sua resposta anterior terminou com \"Aproveitando: …\", foi a agenda que perguntou");
});
