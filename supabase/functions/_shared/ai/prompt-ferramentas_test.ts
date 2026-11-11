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
  // Orçamento pelo cartão (Retorno F3, P8.3): argumento de retorno_orcar_caso
  "mao_de_obra",
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
// Agenda de Produção (25/10/2026, Fase 4, P6): valor da situação de material_informar ("essa nota não é de serviço")
NAO_SAO_TOOLS.add("nao_e_de_servico");
// Agenda de Produção (27/10/2026, Fase 5, P5): argumento de os_planejar ("pro cliente, o serviço é a troca das baterias")
NAO_SAO_TOOLS.add("servico_cliente");
// Agenda de Produção (correção de 29/10, P1): valor do periodo de agenda_ver ("como você pensou a semana que vem?")
NAO_SAO_TOOLS.add("proxima_semana");
// Agenda de Produção (31/10/2026, Fase 7b, P5): argumento de os_planejar ("dois no primeiro dia" = dupla inicio com dupla_meios 2)
// e valor da situação de equipe_disponibilidade ("fulano saiu" = nao_vem com padrao)
NAO_SAO_TOOLS.add("dupla_meios");
// Agenda de Produção (06/11/2026, Fase 7d, P8): argumentos de os_planejar (o local, o bem e as datas ditas)
for (const campo of ["bem_onde", "bem_exige", "descer_quem", "chega_em", "sai_em"]) NAO_SAO_TOOLS.add(campo);
// Fase 7d (correção, Onda 2): "até dia 13" separa os 4 campos que serviam
for (const campo of ["bem_fora", "congelar_ate", "precisa_ate"]) NAO_SAO_TOOLS.add(campo);
NAO_SAO_TOOLS.add("nao_vem");
// Agenda de Produção (01/11/2026, Fase 7c, P8): valor do foco de agenda_ver ("o que o Alex faz amanhã?" = pessoa e período no foco
// o_que_fazer; as etapas de um serviço)
NAO_SAO_TOOLS.add("o_que_fazer");

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
// Fase 4: no máximo 5 a mais (spec-fase4.md §7.3) — entraram 3 (P1: o prazo do fornecedor; P6: a resposta à nota, ao Pix e à
// mensagem do fornecedor, e os focos compras/fornecedores com a pergunta ao fornecedor que é só da agenda). Os outros 2
// itens da spec viraram trechos de linhas que já existiam (a fronteira do *novo*, as palavras que o dono manda direto). O
// teto continua 21: a seção fica em 21.
// Fase 5: mensagens ao cliente (spec-fase5.md §7.3: +3 linhas, teto 24, ou juntar a linha das palavras) — entraram 2 linhas
// (a mensagem-modelo que só o dono manda com *manda cliente*; o prometido e o foco clientes) e as palavras novas foram para a
// linha das palavras que já existia. Teto 23.
// Fase 6 (P8): o aprendizado (spec-fase6.md §7: +1 linha, teto 24) — entrou 1 linha: o que a agenda aprendeu é agenda_ver foco
// aprendizado, os números vêm do banco, nunca mudar parâmetro (é decisão do dono pelas perguntas da agenda), e as duas palavras
// (*agenda aprendizado*, *desfaz aprendizado*) na própria linha (a das palavras de antes fica como está: o teste da Fase 5
// fixa o fim dela). Teto 24.
// Fase 7a (P7): o gestor da agenda (spec-fase7a.md §7: +1 linha, teto 25) — entrou 1 linha: o que ele marcou, marcaria em teste
// e perguntou antes é agenda_ver foco gestor; o modelo nunca marca, calcula data nem escolhe técnico; e as palavras do dono
// (*agenda gestor*, *gestor, só propor*, *gestor, pode marcar*, *<nome> com dupla*) na própria linha. Teto 25.
// Fase 7b (P5): os dias de cada pessoa e a dupla (spec-fase7b.md §7 e §R4.8: +2 linhas, teto 27) — entraram 2 linhas: quem a
// agenda pergunta e quando, a semana dita (equipe_disponibilidade com semana), quem vem sob demanda só nas datas (vem, sem padrao e
// sem semana), os focos equipe e gestor; e a dupla pela tarefa, o os_planejar dupla com dupla_meios e o ajudante que só o dono chama.
// Teto 27.
// Fase 7c (P4): quem faz o quê (spec-fase7c.md §7: +1 linha, o teto sobe 1 a partir do vigente) — entrou 1 linha: o que cada
// pessoa faz, o que uma OS pede e o responsável dela vão para equipe_habilidade (uma chamada por pessoa e por coisa dita, com
// trecho; nunca deduzir nem escolher quem vai), a leitura é agenda_ver foco habilidades e as fronteiras com equipe_disponibilidade
// (quem VAI vir) e com agenda_propor fixar (pôr alguém num dia). Teto 28.
// Fase 7c (P8): as etapas de um serviço (spec-fase7c.md §16.7: +1 linha, o teto sobe 1 a partir do vigente) — entrou 1 linha: ler
// as etapas é agenda_ver com os (ou com pessoa e período no foco o_que_fazer); o que o dono diz delas vai para servico_etapa (uma
// chamada por coisa dita, com trecho; nunca inventar etapa nem dizer quem faz o quê ou em que dia); tarefa do próprio dono não é
// etapa de OS; as fronteiras com agenda_propor fixar e equipe_habilidade. Teto 29.
// Fase 7d (P8): o local, o bem e a viagem (spec-fase7d.md §7 e R6.3-8: +2 linhas, o teto sobe 2 a partir do vigente) — entraram 2 linhas: o que o dono diz do local, do bem,
// da viagem e dos autorizados é os_planejar (a lista inteira de autorizados, as datas como ele disse, o foco locais e a pergunta de onde fica), e regra de marina não muda
// pela conversa, nem se inventa local, regra, feriado ou tempo de viagem. A resposta só com número (P6b) e a nota por número entraram nas 2 linhas que já existiam. Teto 31.
// Fase 7f (P7): o silêncio e o *agenda espera* (spec-fase7f.md §7 e R8.5-28: +2 linhas, o teto sobe 2 a partir do vigente, 31) — entraram 2 linhas: só a pergunta que diz
// "Sem resposta até" fica assim sem resposta (com o freio e em sombra, nenhuma diz: ela espera o dono), a única saída de quem não quer o padrão é *agenda espera <nome>*,
// *agenda fica* não existe ("pode deixar como você propôs" não grava nada) e nada é decidido pelo prazo sem o banco dizer; e a informação só quando o dono pergunta. Teto 33.
// Fase 7e (P8): a margem (spec-fase7e.md §7 e R7.5-24: nenhuma linha nova, o teto fica 33) — tudo na linha do aprendizado que já existia: a margem no foco aprendizado, o prazo
// real só para o dono (AG7-32: ao cliente não se diz data de pronto), o que é urgente e as palavras dias e semana do *desfaz aprendizado <coisa>*.
Deno.test("agenda de produção: a seção é curta (≤ 33 linhas: custa tokens em toda mensagem) e fica no bloco estável", () => {
  const secao = secaoDaAgenda();
  const linhas = secao.split("\n");
  assertEquals(linhas.length <= 33, true, `a seção tem ${linhas.length} linhas`);
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
  // material_informar com novo × add_service_order_item (a peça que entra no orçamento). FASE 4 (P6): o *novo* entra na
  // lista do que comprar, sem preço (P2: a linha do dono na compra e na R16) — a fronteira é o orçamento, não a compra.
  assertStringIncludes(secao, "equipe_disponibilidade é quem VAI vir");
  // PÓS-MERGE (A, 28/10/2026): a falta não se lança mais (registrar_diaria recusa) — o dia sem trabalho fica sem diária.
  assertStringIncludes(secao, "(\"não veio hoje\", \"faltou ontem\") não se lança: fica sem diária");
  assertStringIncludes(secao, "material_informar com novo põe a peça na lista do que comprar (sem preço), não no orçamento: para cobrar, add_service_order_item");
  assertEquals(secao.includes("só avisa a agenda e não põe a peça na OS nem na compra"), false, "sobrou a fronteira antiga do novo");
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

// Agenda de Produção (25/10/2026, Fase 4, P6): o material em sincronia com o fornecedor — a resposta do dono à pergunta da
// nota, do Pix ou da mensagem do fornecedor (material_informar com aviso; "não é de serviço"), os focos compras e
// fornecedores (cada um existe no enum), a pergunta ao fornecedor que é só da agenda (o modelo nunca manda, nunca compra
// nem paga) e as palavras *agenda compras* e *agenda fornecedores* (o comando sem IA lê cada uma). Nenhuma ferramenta nova
// à vista: o teto do perfil continua.
Deno.test("agenda de produção (Fase 4, P6): o aviso da nota/Pix/mensagem, os focos compras e fornecedores, o fornecedor só pela agenda e as palavras", () => {
  const secao = secaoDaAgenda();
  // 1. a resposta à pergunta da agenda: material_informar com aviso; "não é de serviço" é a situação, com o aviso
  assertStringIncludes(secao, "material_informar com aviso = como ele chamou a nota, o Pix ou a mensagem");
  assertStringIncludes(secao, "\"essa nota não é de serviço\" é situacao nao_e_de_servico com o aviso, sem OS");
  const material = porNome.get("material_informar")!.input_schema as {
    properties: Record<string, { enum?: string[] }>;
  };
  assertEquals("aviso" in material.properties, true, "material_informar sem aviso");
  assertEquals(material.properties.situacao.enum?.includes("nao_e_de_servico"), true, "nao_e_de_servico não é situação");
  // 2. os focos novos existem no enum de agenda_ver, e a descrição da ferramenta cita os dois
  const agendaVer = porNome.get("agenda_ver")!;
  const focos = (agendaVer.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  for (const foco of ["compras", "fornecedores"]) {
    assertStringIncludes(secao, `foco ${foco}`);
    assertEquals(focos.includes(foco), true, `${foco} não é foco de agenda_ver`);
    assertStringIncludes(agendaVer.description, `(foco ${foco}`);
  }
  // 3. a pergunta ao fornecedor é só da agenda; o modelo nunca manda, nunca compra nem paga
  assertStringIncludes(secao, "A agenda pergunta sozinha ao fornecedor se a entrega continua na data");
  assertStringIncludes(secao, "você nunca manda mensagem ao fornecedor por conta própria e nunca compra, paga nem cria OC ou cotação");
  // 4. as palavras que o dono manda direto: o comando sem IA LÊ cada uma (e são de ver: não agem)
  // (Fase 5, P5) a linha das palavras ganhou *manda cliente*, *segura cliente* e *agenda clientes* depois destas
  assertStringIncludes(secao, "*agenda compras*, *agenda fornecedores*, *manda cliente [nome]*");
  for (const [palavra, foco] of [["agenda compras", "compras"], ["agenda fornecedores", "fornecedores"]]) {
    const c = lerComandoDaAgenda(palavra);
    assertEquals(c?.comando === "ver" ? c.foco : null, foco, palavra);
  }
  // 5. a pergunta dos principais (P5, no banco) cita a palavra que existe
  assertEquals(lerComandoDaAgenda("*agenda fornecedores*")?.comando, "ver");
});

// Agenda de Produção (27/10/2026, Fase 5, P5): as mensagens ao cliente — a agenda manda sozinha só as mensagens-modelo; o
// pedido do dono é cliente_avisar (prepara, e só sai com *manda cliente*); a mensagem livre continua do assistente; o que
// foi dito ao cliente é os_planejar com prometido; o foco clientes; e as palavras que o dono manda direto (o comando sem IA
// LÊ cada uma).
Deno.test("agenda de produção (Fase 5, P5): a mensagem-modelo só com *manda cliente*, a mensagem livre do assistente, o prometido, o foco clientes e as palavras", () => {
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "você nunca manda mensagem a cliente por conta da agenda");
  assertStringIncludes(secao, "é cliente_avisar com o tipo, e ela só sai com *manda cliente Nelson*");
  assertStringIncludes(secao, "Texto livre ao cliente continua sendo a mensagem do assistente, com a confirmação de sempre");
  assertStringIncludes(secao, "cobrança, valor e desconto nunca vão pela agenda");
  assertStringIncludes(secao, "é os_planejar com prometido = como ele disse");
  assertStringIncludes(secao, "agenda_ver foco clientes");
  assertStringIncludes(secao, "Decisão de aviso de atraso (ligar ou mandar): agenda_ver foco decisoes e agenda_aplicar com decisao e opcao");
  assertEquals(porNome.has("cliente_avisar"), true);
  assertEquals(SO_PELA_REDE.has("cliente_avisar"), true);
  const focos = (porNome.get("agenda_ver")!.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  assertEquals(focos.includes("clientes"), true);
  const plan = (porNome.get("os_planejar")!.input_schema as { properties: Record<string, unknown> }).properties;
  assertEquals("prometido" in plan && "servico_cliente" in plan, true);
  assertStringIncludes(secao, "*manda cliente [nome]*, *segura cliente [nome]* e *agenda clientes* o dono manda direto, sem você");
  assertEquals(lerComandoDaAgenda("manda cliente Nelson")?.comando, "cliente");
  assertEquals(lerComandoDaAgenda("segura cliente")?.comando, "cliente");
  const ver = lerComandoDaAgenda("agenda clientes");
  assertEquals(ver?.comando === "ver" ? ver.foco : null, "clientes");
});

// Agenda de Produção (28/10/2026, Fase 6, P8): o aprendizado — o foco aprendizado (existe no enum e na descrição de
// agenda_ver), os números do banco, nunca mudar parâmetro ("muda o fator", "liga o aprendizado": é decisão do dono pelas
// perguntas da agenda e pelo roteiro dos OKs) e as palavras que o dono manda direto (o comando sem IA LÊ cada uma). Nenhuma
// ferramenta nova: o teto do perfil continua.
Deno.test("agenda de produção (Fase 6, P8): o foco aprendizado, os números do banco, nunca mudar parâmetro e as palavras", () => {
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "agenda_ver foco aprendizado");
  assertStringIncludes(secao, "Os números vêm do banco; nunca calcule nem mude parâmetro");
  assertStringIncludes(secao, "mudar é decisão do dono pelas perguntas da agenda");
  assertStringIncludes(secao, "*agenda aprendizado* e *desfaz aprendizado* o dono manda direto, sem você");
  // Fase 6 (correção C2, item 6): o *desfaz aprendizado <coisa>* volta só ela (o comando sem IA a LÊ)
  // (7e P8, R7.5-18) + dias (o tempo das OS) e semana (a folga da semana): mudança deliberada da frase
  assertStringIncludes(secao, "*desfaz aprendizado* com a coisa (fator, presença, valor, folga, capacidade, dias, semana ou o nome do fornecedor, como *desfaz aprendizado Kamell*) volta só ela");
  const so = lerComandoDaAgenda("desfaz aprendizado Kamell");
  assertEquals(so?.comando === "desfazer" ? so.alvo : null, "aprendizado kamell");
  const agendaVer = porNome.get("agenda_ver")!;
  const focos = (agendaVer.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  assertEquals(focos.includes("aprendizado"), true);
  assertStringIncludes(agendaVer.description, "(foco aprendizado");
  const ver = lerComandoDaAgenda("agenda aprendizado");
  assertEquals(ver?.comando === "ver" ? ver.foco : null, "aprendizado");
  const desfaz = lerComandoDaAgenda("desfaz aprendizado");
  assertEquals(desfaz?.comando === "desfazer" ? desfaz.alvo : null, "aprendizado");
  // sem crase no texto ensinado (o prompt é um template literal)
  assertEquals(secao.includes("`"), false);
});

// Agenda de Produção (Fase 7e, P8; spec-fase7e.md §7, R7.3-1, R7.5-18, R7.5-24): a margem entra na linha do aprendizado (nenhuma linha nova): o que ela mede, o prazo real só
// para o dono (AG7-32: ao cliente não se diz data de pronto, nem pelo modelo), o que é urgente (o banco decide a folga) e as palavras dias e semana, que chegam ao banco pelo
// leitor de comandos de hoje (o alvo de 2 palavras do *desfaz*). "compra" não chega (NOVO-agenda-220: comandos.ts é de whatsapp-webhook e ai-daily-briefing, que a 7e não
// publica): por isso não está na frase.
Deno.test("agenda de produção (Fase 7e, P8): a margem na linha do aprendizado, o prazo real só para o dono, a urgência e as palavras dias e semana", () => {
  const secao = secaoDaAgenda();
  const linha = secao.split("\n").find((l) => l.startsWith("- O que a agenda aprendeu com o que aconteceu")) ?? "";
  assertStringIncludes(linha, "e a margem (quanto o serviço costuma passar da estimativa, a folga da semana, o prazo real, o seu tempo de compra): agenda_ver foco aprendizado");
  assertStringIncludes(linha, "O prazo real é só para o dono: ao cliente a agenda não diz data de pronto, e você também não.");
  assertStringIncludes(linha, "Urgente é o serviço que passa na frente (prioridade 1) ou que o cliente precisa logo: o banco decide se ele usa a folga.");
  assertStringIncludes(linha, "\"aumenta a folga\"");
  // as palavras novas da frase chegam ao banco como o *desfaz <alvo>* (o banco resolve "aprendizado dias" e "aprendizado semana": agenda_desfazer_dito, 20261111100600)
  for (const coisa of ["dias", "semana"]) {
    const c = lerComandoDaAgenda(`desfaz aprendizado ${coisa}`);
    assertEquals(c?.comando === "desfazer" ? c.alvo : null, `aprendizado ${coisa}`);
  }
  // a palavra que não chega não é ensinada
  assertEquals(linha.includes("semana, compra"), false);
  assertEquals(linha.includes("`"), false);
});

// Correção de 29/10 (P1): as frases naturais do dono ("quais estão agendados?", "como você pensou a semana que vem?",
// "quando tenho agenda livre?") caíam no modelo sem roteiro. As inequívocas viraram palavra (comandos.ts); as variações
// (com o dia, com outra palavra, "quando tem vaga?") o prompt manda ao foco e ao período certos — na linha do publicado,
// sem linha nova (o teto da seção continua 24).
Deno.test("agenda de produção (correção 29/10, P1): as frases naturais vão ao foco plano, à semana que vem ou ao livre", () => {
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "\"Quais estão agendados?\", \"o que tem agendado?\", \"o que você marcou?\": foco plano sem periodo (de hoje ao sábado da semana que vem, com quem vai; com o dia dito, periodo = o dia como ele disse)");
  assertStringIncludes(secao, "\"Como você pensou a semana que vem?\", \"como ficou a agenda da semana que vem?\": periodo proxima_semana sem foco (o plano e o porquê de quem ficou de fora)");
  assertStringIncludes(secao, "\"Quando tenho agenda livre?\", \"quando estou livre?\", \"quando tem vaga?\": foco livre");
  // o que o prompt ensina é o que a palavra lê (a mesma leitura pelo modelo e sem ele): o foco e o período existem
  const agendaVer = porNome.get("agenda_ver")!;
  const focos = (agendaVer.input_schema as { properties: Record<string, { enum?: string[] }> }).properties.foco.enum ?? [];
  for (const f of ["plano", "livre"]) assertEquals(focos.includes(f), true, `${f} não é foco de agenda_ver`);
  const comoPalavra = (t: string) => {
    const c = lerComandoDaAgenda(t);
    return c?.comando === "ver" ? `${c.foco}/${c.periodo}` : null;
  };
  assertEquals(comoPalavra("Quais estão agendados?"), "plano/null");
  assertEquals(comoPalavra("o que tem agendado?"), "plano/null");
  assertEquals(comoPalavra("o que você marcou?"), "plano/null");
  assertEquals(comoPalavra("Como você pensou a semana que vem?"), "tudo/proxima_semana");
  assertEquals(comoPalavra("como ficou a agenda da semana que vem?"), "tudo/proxima_semana");
  assertEquals(comoPalavra("Quando tenho agenda livre?"), "livre/null");
  assertEquals(comoPalavra("quando estou livre?"), "livre/null");
  // "quando tem vaga?" sozinho não é palavra (vaga também é de marina): é o modelo que o leva ao foco livre
  assertEquals(comoPalavra("quando tem vaga?"), null);
  assertEquals(secao.includes("`"), false);
});

// Correção de 29/10 (P2): o *livre* passou a ser UMA resposta (a do plano) e termina com "Para um serviço novo, me diga
// quantos dias e com quem, que eu digo o 1º dia que cabe." A resposta do dono ("3 dias com o Roberto", sem OS) é o serviço
// que ainda não existe — agenda_ver com simular, que agora é o encaixe do motor —, não um fato de os_planejar ("são dois
// dias" de uma OS). Na mesma linha do livre, sem linha nova (o teto da seção continua 24).
Deno.test("agenda de produção (correção 29/10, P2): o serviço novo depois do livre é agenda_ver simular, não os_planejar", () => {
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "\"Quando tenho agenda livre?\", \"quando estou livre?\", \"quando tem vaga?\": foco livre. Serviço que ainda não existe (\"se entrar um de 2 dias, quando dá?\"; ou, logo depois do livre, \"3 dias com o Roberto\" sem dizer a OS): agenda_ver com simular, os dias e com quem ele disse (só simula; não é os_planejar).");
  const agendaVer = porNome.get("agenda_ver")!;
  const props = (agendaVer.input_schema as { properties: Record<string, { properties?: Record<string, unknown>; description?: string }> }).properties;
  assertEquals(Object.keys(props.simular.properties ?? {}).sort(), ["com_quem", "dias", "dono"]);
  assertStringIncludes(props.simular.description ?? "", "o 1º dia que cabe pelo plano de agora. Só simula: não marca nem reserva nada.");
  assertEquals(porNome.has("os_planejar"), true);
  assertEquals(secao.includes("`"), false);
  // (Fase 7a, P7) o teto da seção passou a 25 (a linha do gestor da agenda); (Fase 7b, P5) a 27 (os dias de cada pessoa e a dupla);
  // (Fase 7c, P4) a 28 (quem faz o quê); (Fase 7c, P8) a 29 (as etapas de um serviço);
  // (Fase 7d, P8) a 31 (o local e a regra de marina); (Fase 7f, P7) a 33 (o silêncio e o *agenda espera*)
  assertEquals(secao.split("\n").length <= 33, true);
});

// Fase 7b (P5; spec-fase7b.md §7 e §R4.8): as 2 linhas novas ensinam o que as ferramentas têm de verdade — a semana de
// equipe_disponibilidade, quem vem sob demanda só nas datas (vem, sem padrao e sem semana), os focos equipe e gestor, o os_planejar
// dupla com os valores do enum e o dupla_meios — e nunca mandam o modelo escolher quem vai nem calcular dias.
Deno.test("agenda de produção (Fase 7b, P5): os dias de cada pessoa e a dupla, amarrados aos esquemas das ferramentas", () => {
  const secao = secaoDaAgenda();
  const dias = secao.split("\n").find((l) => l.startsWith("- Os dias de cada pessoa:"))!;
  const dupla = secao.split("\n").find((l) => l.startsWith("- Dupla: a agenda supõe 1 pessoa"))!;
  assertEquals(!!dias && !!dupla, true, "as 2 linhas da 7b sumiram");
  assertStringIncludes(dias, "a agenda pergunta toda quinta a quem está na rotina com telefone, e ao dono só quando faz diferença");
  assertStringIncludes(dias, "equipe_disponibilidade com semana como ele disse");
  assertStringIncludes(dias, "\"o Mateus vem quarta e quinta\" (quem ele chama quando precisa) é vem, sem padrao e sem semana (só nessas datas)");
  assertStringIncludes(dias, "agenda_ver foco equipe; quem chamar: foco gestor");
  assertStringIncludes(dias, "Nunca calcule capacidade nem diga dias que o banco não deu.");
  assertStringIncludes(dupla, "os_planejar dupla: \"vai com um só\" é nao; \"precisa de dois o tempo todo\" é todos; \"dois no primeiro dia\" é inicio com dupla_meios 2");
  assertStringIncludes(dupla, "a agenda marca com 1 e diz em que dias chamar um ajudante; quem chama é o dono. Nunca escolha quem vai.");
  // o que as linhas citam existe nos esquemas
  const disp = porNome.get("equipe_disponibilidade")!;
  const dp = (disp.input_schema as { properties: Record<string, unknown> }).properties;
  assertEquals(["semana", "padrao"].every((k) => k in dp), true);
  const plan = porNome.get("os_planejar")!;
  const pp = (plan.input_schema as { properties: Record<string, { enum?: string[] }> }).properties;
  assertEquals(pp.dupla.enum, ["nao", "inicio", "fim", "todos"]);
  assertEquals("dupla_meios" in pp, true);
  const ver = porNome.get("agenda_ver")!;
  const focos = (ver.input_schema as { properties: { foco: { enum: string[] } } }).properties.foco.enum;
  assertEquals(focos.includes("equipe") && focos.includes("gestor"), true);
  assertEquals(secao.includes("`"), false);
});

// Fase 7c (P4; spec-fase7c.md §7): a linha nova ensina o que a ferramenta tem de verdade — equipe_habilidade (rede, fora do perfil:
// SO_PELA_REDE), uma chamada por pessoa e por coisa dita com trecho, o foco habilidades — e nunca manda o modelo deduzir o que a pessoa
// faz nem escolher quem vai; as fronteiras são ferramentas de verdade (equipe_disponibilidade, agenda_propor com fixar).
Deno.test("agenda de produção (Fase 7c, P4): quem faz o quê é equipe_habilidade, amarrado ao esquema; o foco habilidades; as fronteiras", () => {
  const secao = secaoDaAgenda();
  const linha = secao.split("\n").find((l) => l.startsWith("- Quem faz o quê (instala sozinho, é ajudante, é novo, comissiona Victron, sobe no teto)"))!;
  assertEquals(!!linha, true, "a linha da 7c sumiu");
  assertStringIncludes(linha, "o que uma OS pede e quem é o responsável dela: equipe_habilidade, uma chamada por pessoa e por coisa dita, com trecho");
  assertStringIncludes(linha, "nunca deduza o que a pessoa faz nem escolha quem vai (quem escala é a agenda)");
  assertStringIncludes(linha, "Para ler: agenda_ver foco habilidades.");
  assertStringIncludes(linha, "Fronteiras: quem VAI vir num dia é equipe_disponibilidade; pôr alguém num dia é agenda_propor com fixar.");
  // a ferramenta existe, está ao alcance (pela rede, fora do perfil) e tem o que a linha cita
  const hab = porNome.get("equipe_habilidade")!;
  assertEquals(!!hab, true, "equipe_habilidade não é ferramenta");
  assertEquals(SO_PELA_REDE.has("equipe_habilidade"), true);
  assertEquals(PERFIL_OPERACAO.has("equipe_habilidade"), false);
  const hp = (hab.input_schema as { properties: Record<string, unknown>; required: string[] });
  assertEquals(["pessoa", "o_que_faz", "os", "exige", "meios", "lider", "confirmar", "trecho"].every((k) => k in hp.properties), true);
  assertEquals(hp.required, ["trecho"]);
  const ver = porNome.get("agenda_ver")!;
  const focos = (ver.input_schema as { properties: { foco: { enum: string[] } } }).properties.foco.enum;
  assertEquals(focos.includes("habilidades"), true);
  const propor = porNome.get("agenda_propor")!;
  assertEquals("fixar" in (propor.input_schema as { properties: Record<string, unknown> }).properties, true);
  assertEquals(porNome.has("equipe_disponibilidade"), true);
  // *agenda quem faz* e "quem faz o quê" são palavras do dono (de ver), lidas antes do modelo
  const c = lerComandoDaAgenda("quem faz o quê?");
  assertEquals(c?.comando === "ver" ? c.foco : null, "habilidades");
  assertEquals(secao.includes("`"), false);
});

// Fase 7c (P8; spec-fase7c.md §16.7): a linha nova ensina o que a ferramenta tem de verdade — servico_etapa (rede, fora do perfil:
// SO_PELA_REDE), uma chamada por coisa dita com trecho, a leitura pelo agenda_ver com os ou com pessoa no foco o_que_fazer — e nunca
// manda o modelo inventar etapa nem dizer quem faz o quê ou em que dia; as fronteiras são ferramentas de verdade.
Deno.test("agenda de produção (Fase 7d, P8): o local é os_planejar, amarrado ao esquema; regra de marina não muda pela conversa; a resposta só com número", () => {
  const secao = secaoDaAgenda();
  // 1. as 2 linhas da §7, como a spec dá
  assertStringIncludes(secao, "Onde é o serviço, se o barco está na água ou em seco, quem desce, quando o motorhome chega ou sai, se é viagem e quem está autorizado na marina: os_planejar (local, bem_onde, bem_exige, descer_quem, chega_em, sai_em, viagem, autorizados), só com o que o dono disse e as palavras dele.");
  assertStringIncludes(secao, "Para ver: agenda_ver foco locais");
  // (correção O11 = C3 = R2) "fica anotado" saiu: nada guarda o que ele disser da regra, e a frase era dita ao próprio dono
  assertStringIncludes(secao, "Regra de marina ou de pátio (horário, sábado, autorização, seguro, tomada, vagas) não muda pela conversa, e nada guarda o que ele disser dela: diga que por aqui você não muda a regra do local, que vale o que está no cadastro e que o ajuste é feito com o OK dele, fora da conversa. Nunca diga \"anotado\" nem \"fica registrado\". Nunca invente local, regra, feriado nem tempo de viagem.");
  assertEquals(secao.includes("fica anotado"), false);
  // 2. os campos ensinados existem no esquema (tool registrada não é tool ensinada, e o contrário também)
  const planejar = porNome.get("os_planejar")!.input_schema as { properties: Record<string, any> };
  for (const c of ["local", "bem_onde", "bem_exige", "descer_quem", "chega_em", "sai_em", "viagem", "autorizados"]) {
    assertEquals(c in planejar.properties, true, c);
  }
  assertEquals(planejar.properties.limpar.items.enum.includes("autorizados"), true);
  // 3. o maior risco do P7: autorizados é a lista inteira; a data vai como ele disse
  assertStringIncludes(secao, "autorizados é a lista INTEIRA (\"o João também\" = quem já estava + o João");
  assertStringIncludes(secao, "chega_em e sai_em como ele disse (\"dia 5\")");
  // 4. a pergunta de onde fica: com opções, como as decisões; sem, os_planejar
  assertStringIncludes(secao, "A pergunta de onde fica que tem opções se responde como as decisões (agenda_aplicar); a que pede \"me diga onde é\" e a de quem respondeu sem dizer onde são os_planejar.");
  // 5. a resposta só com número (P6b): opcao sem decisao, o número e não o texto, o trecho literal, a volta como veio; a nota por número
  assertStringIncludes(secao, "Só um número (\"1\", \"a 2\") é opcao, sem decisao: decisao só com a que ele disse; opcao é sempre o número, não o texto da opção; trecho = as palavras dele, sem completar; se voltar \"Qual decisão? …\", mande como veio.");
  assertStringIncludes(secao, "Número dito à nota ou ao Pix (\"na nota, a 2\"): as notas abertas estão em agenda_ver foco compras, e as opções de cada uma, na pergunta dela em agenda_ver foco decisoes; com 2 notas abertas, ou sem as opções no texto, pergunte qual, sem adivinhar; depois, a OS daquela opção, em material_informar com o aviso; a última opção (\"nenhum\") é nao_e_de_servico.");
  // (correção, Onda 2) o lugar novo, a data com o verbo, "até dia 13", a lista, e as linhas do entregue param de competir
  assertStringIncludes(secao, "Lugar fora do cadastro vai em local como ele disse: a releitura avisa que é lugar novo, e você não diz \"não achei\"");
  assertStringIncludes(secao, "\"outro lugar\" vai como local \"outro lugar em Itajaí\"");
  // (correção, Onda 4, M5) a saída das recusas: o prefixo é do banco, e o modelo não o tira
  assertStringIncludes(secao, "\"lugar novo: X\" vai em local inteiro");
  assertStringIncludes(secao, "com o verbo dele no trecho (\"chegou dia 5\"): quem decide o mês é o banco");
  assertStringIncludes(secao, "\"Até dia 13\": sobre o bem na HBR ou no pátio é sai_em, que leva \"dia 13\", sem o \"até\"; prazo do cliente é precisa_ate; o bem indisponível é bem_fora; congelar_ate só com \"não mexe até\".");
  // (correção, Onda 3, G6, T8) o que não é lugar não vai em local; "em seco" junto do lugar vai em bem_onde; a ferramenta para de dizer "pergunta se não achar"
  assertStringIncludes(secao, "O que não é nome de lugar (\"depois te digo\", \"tanto faz\", \"longe\") não vai em local: pergunte onde é.");
  assertStringIncludes(secao, "\"Em seco\" ou \"na água\" junto do lugar vai em bem_onde, e local leva só o lugar.");
  assertEquals(porNome.get("os_planejar")!.description.includes("pergunta se não achar"), false);
  assertStringIncludes(porNome.get("os_planejar")!.description, "lugar fora do cadastro vai como ele disse, e a releitura avisa");
  for (const c of ["sai_em", "precisa_ate", "bem_fora", "congelar_ate"]) assertEquals(c in planejar.properties, true, c);
  assertEquals(String(planejar.properties.bem_fora.description).includes("até dia 3"), false, "o exemplo ambíguo saiu");
  assertStringIncludes(secao, "leia antes em agenda_ver foco locais com os; sem conseguir ler, pergunte quem mais está");
  assertStringIncludes(secao, "Serviço que terminou ou foi entregue não é resposta a decisão, mesmo com pergunta aberta dele: é a linha de baixo.");
  assertStringIncludes(secao, "é evento concluiu ou entregou, com a OS no plano ou fora dele: é o mesmo caminho do *entreguei*, nunca agenda_aplicar");
  // 6. a descrição da ferramenta diz o mesmo
  const aplicar = porNome.get("agenda_aplicar")!;
  assertStringIncludes(aplicar.description, "só um número = opcao, sem decisao");
  assertEquals(aplicar.description.includes("crítica"), false);
});

Deno.test("agenda de produção (Fase 7c, P8): as etapas de um serviço são servico_etapa, amarrado ao esquema; a leitura; as fronteiras", () => {
  const secao = secaoDaAgenda();
  const linha = secao.split("\n").find((l) => l.startsWith("- Etapas de um serviço (o que já foi feito e o que falta numa OS, e o que cada um faz no dia)"))!;
  assertEquals(!!linha, true, "a linha do P8 sumiu");
  assertStringIncludes(linha, "para ler, agenda_ver com os (ou com pessoa e período no foco o_que_fazer)");
  assertStringIncludes(linha, "servico_etapa, uma chamada por coisa dita, com trecho");
  assertStringIncludes(linha, "nunca invente etapa, nunca diga quem faz o quê nem em que dia (quem distribui e cobra é a agenda)");
  assertStringIncludes(linha, "Tarefas e lembretes do próprio dono não são etapas de OS.");
  assertStringIncludes(linha, "Fronteira: quem VAI num dia é agenda_propor com fixar; quem é o responsável da OS é equipe_habilidade.");
  // a ferramenta existe, está ao alcance (pela rede, fora do perfil) e tem o que a linha cita
  const et = porNome.get("servico_etapa")!;
  assertEquals(!!et, true, "servico_etapa não é ferramenta");
  assertEquals(SO_PELA_REDE.has("servico_etapa"), true);
  assertEquals(PERFIL_OPERACAO.has("servico_etapa"), false);
  const ep = (et.input_schema as { properties: Record<string, { enum?: string[] }>; required: string[] });
  assertEquals(Object.keys(ep.properties), ["os", "etapa", "estado", "texto", "partes", "trecho"]);
  assertEquals(ep.properties.estado.enum, ["feita", "falta", "nao_se_aplica"]);
  assertEquals(ep.required, ["os", "trecho"]);
  const ver = porNome.get("agenda_ver")!;
  const vp = (ver.input_schema as { properties: Record<string, { enum?: string[] }> }).properties;
  assertEquals(["os", "pessoa", "periodo"].every((k) => k in vp) && (vp.foco.enum ?? []).includes("o_que_fazer"), true);
  const propor = porNome.get("agenda_propor")!;
  assertEquals(porNome.has("equipe_habilidade") && "fixar" in (propor.input_schema as { properties: Record<string, unknown> }).properties, true);
  assertEquals(secao.includes("`"), false);
});

// PÓS-MERGE (A, 28/10/2026): "faltou" não se lança mais — registrar_diaria recusa a falta (main, Diárias fase 1b). O texto
// que o modelo lê não pode mandar o dia sem trabalho para registrar_diaria: ele chamaria, levaria a recusa e daria uma
// volta a mais. A regra nova: dia sem trabalho fica sem diária (nada a lançar); dito com a OS do plano, o fato vai por
// os_registrar_andamento; quem VAI faltar é equipe_disponibilidade; lançado por engano = apagar.
Deno.test("pós-merge (A): o dia sem trabalho não vai para registrar_diaria — sem diária, andamento na OS do plano, futuro na disponibilidade, engano = apagar", () => {
  const texto = textoDoPrompt();
  assertEquals(texto.includes("jornada='faltou'"), false, "o prompt ainda manda jornada='faltou'");
  assertEquals(texto.includes("é 'faltou'"), false, "o prompt ainda manda 'faltou' no lugar do apagar");
  assertEquals(/faltou ontem"\) é registrar_diaria/.test(texto), false, "o prompt ainda manda \"faltou ontem\" para registrar_diaria");
  assertEquals(texto.includes("trabalhou ou faltou"), false, "a diária de quem faltou não existe mais");
  assertEquals(texto.includes("inteiro, meio ou falta"), false, "não se pergunta se foi falta: falta não se lança");
  assertEquals(texto.includes("\"faltou desde 19/09\" →"), false, "o exemplo do intervalo não pode ser uma falta");
  // A seção das diárias ensina a regra nova, com as vizinhas certas.
  const i = texto.indexOf("════ DIÁRIAS DE FREELANCERS");
  const diarias = texto.slice(i, texto.indexOf("\n════", i + 10));
  assertStringIncludes(diarias, "dia sem trabalho não se lança");
  assertStringIncludes(diarias, "os_registrar_andamento");
  assertStringIncludes(diarias, "equipe_disponibilidade");
  assertStringIncludes(diarias, "jornada='apagar'");
  // A seção da agenda: a fronteira com registrar_diaria passa a dizer que a falta fica sem diária.
  const secao = secaoDaAgenda();
  assertStringIncludes(secao, "(\"não veio hoje\", \"faltou ontem\") não se lança: fica sem diária");
  // E o que as ferramentas dizem ao modelo: nenhuma descrição manda a falta para registrar_diaria.
  for (const t of allTools) {
    assertEquals(/faltou[^.;]{0,20}\) é registrar_diaria/.test(t.description), false, `${t.name} manda a falta para registrar_diaria`);
  }
  const diaria = porNome.get("registrar_diaria")!.input_schema as { properties: Record<string, any> };
  assertEquals(diaria.properties.jornada.enum.includes("faltou"), false);
  assertEquals(diaria.properties.dias.items.properties.jornada.enum.includes("faltou"), false);
});

// Fase 7f (P7; spec-fase7f.md §7 e R8.5-28): as 2 linhas novas. O silêncio é a resposta só onde o prazo está escrito ("Sem resposta até"); a única saída de quem não quer
// o padrão é a palavra *agenda espera <nome>*, do dono e antes do modelo, e *agenda fica* não aparece: não existe. "Pode deixar como você propôs" não grava nada (S120, e
// S124 com o freio: a pergunta continua esperando o dono).
Deno.test("agenda de produção (Fase 7f, P7): o silêncio e o *agenda espera*, sem *agenda fica*; a informação só quando o dono pergunta", () => {
  const secao = secaoDaAgenda();
  // (conferência do P7, 08/11) o silêncio só vale onde o prazo está escrito: com o freio (gestor_so_propor, a produção) e em sombra nenhuma linha diz
  // "Sem resposta até" (agenda_fase7f_leituras.sql), e a frase de antes ("toda pergunta já diz… sem resposta, fica assim") faria o assistente prometer o que não acontece
  assertStringIncludes(secao, "- O prazo de uma pergunta da agenda vem do banco: só a que diz \"Sem resposta até\" fica como ela diz se o dono não responder; a que não diz espera a resposta dele.");
  assertStringIncludes(secao, "\"Pode deixar como você propôs\" não grava nada: com o prazo escrito, é só não responder; sem ele, diga que a pergunta continua esperando a resposta dele.");
  assertEquals(/toda pergunta da agenda já diz/i.test(secao), false);
  assertEquals(/sem resposta, fica assim/i.test(secao), false);
  assertStringIncludes(secao, "Para uma pergunta esperar por ele, sem prazo: *agenda espera <nome>*, que ele manda direto, sem você.");
  assertStringIncludes(secao, "Nunca diga que algo ficou decidido pelo prazo sem o banco dizer.");
  assertStringIncludes(secao, "- Informação (o que está marcado, o que está livre, as compras, o que mudou) só quando o dono pergunta: não ofereça sozinho nem repita o que o fechamento já disse.");
  assertEquals(/agenda fica/i.test(secao), false);
  assertEquals(secao.includes("`"), false);
  // a palavra é do dono: o leitor da agenda a lê antes do modelo; "agenda fica" e o pedido em conversa vão ao modelo
  assertEquals(lerComandoDaAgenda("agenda espera Nelson"), { comando: "veto", acao: "espera", alvo: "nelson" });
  assertEquals(lerComandoDaAgenda("agenda fica"), null);
  assertEquals(lerComandoDaAgenda("pode deixar como você propôs"), null);
});

// Retorno F3 (P8.3): as três ferramentas do orçamento pelo cartão são ensinadas, com as regras que não podem cair.
Deno.test("ORÇAMENTO PELO CARTÃO: o prompt ensina as três ferramentas e as regras", () => {
  const texto = textoDoPrompt();
  const bloco = texto.slice(texto.indexOf("ORÇAMENTO PELO CARTÃO:"));
  assertEquals(bloco.startsWith("ORÇAMENTO PELO CARTÃO:"), true, "o bloco sumiu");
  const trecho = bloco.slice(0, bloco.indexOf("════"));
  for (const nome of ["consultar_proposta_do_caso", "retorno_orcar_caso", "retorno_cadastrar_unidade"]) {
    assertEquals(trecho.includes(nome), true, nome);
    assertEquals(PERFIL_OPERACAO.has(nome), true, `${nome} fora do perfil de operação`);
  }
  for (const regra of [
    "Nunca invente preço, item, título ou cliente",
    "nunca o nome",
    "Quem pede o PIN e mostra as linhas é o sistema",
    "nunca create_vessel",
    "com client_id, nunca com nome",
  ]) assertEquals(trecho.includes(regra), true, regra);
});
