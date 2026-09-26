// Perfil "operacao" de ferramentas do agente — o que entra em TODO turno quando
// app_settings.ai_tool_profile = 'operacao' (_shared/ai/agent.ts, aplicarPerfilDeTools).
//
// DE ONDE VEIO (D18, decisão do dono de 17/09/2026): as 194 tools custavam ~35 mil tokens por
// chamada e 138 nunca tinham sido usadas. O perfil = as tools usadas nos últimos 60 dias de
// auditoria (ai_operator_audit) mais as essenciais do dia a dia. Além desta lista, o turno
// recebe sempre as tools de risco ALTO (o sino precisa encontrá-las) e qualquer tool cujo nome
// apareça no pedido do usuário.
//
// POR QUE A LISTA SAIU DO BANCO (26/09/2026): ela morava em app_settings.ai_tool_profile_operacao,
// editada à mão, e nada a cruzava com o prompt. Resultado: 32 ferramentas que o prompt ENSINAVA
// estavam escondidas pelo perfil, e o modelo, ao obedecer o prompt, recebia "Tool desconhecida"
// — aconteceu em 25/09 com send_document_pdf_to_self ("me manda o PDF do orçamento"). Com a lista
// no código, prompt-ferramentas_test.ts cruza prompt × perfil × SO_PELA_REDE e o descompasso
// quebra o teste antes do deploy, não a conversa do dono. O banco guarda só o liga/desliga (a
// chave velha continua lá, marcada SEM EFEITO, só para uma volta a versão antiga da edge).
//
// CUSTO DE ACRESCENTAR: cada tool daqui custa ~256 tokens por chamada, mas fica no prefixo em
// cache (paga ~10% disso). O que NÃO pode é a lista variar por mensagem: o bloco de tools é o
// começo do prompt cacheado, e um conjunto que muda a cada assunto dá cache miss em toda chamada.
// Por isso é lista FIXA, e a mudança vale no deploy seguinte da edge (antes: em até 5 minutos).
//
// Ordem dos nomes aqui não importa: quem decide a ordem enviada ao modelo é allTools (ordenada
// por nome em tools/index.ts), que é o que mantém o prefixo estável.

/** Ferramentas do perfil de operação. Agrupadas por assunto só para leitura. */
export const PERFIL_OPERACAO: ReadonlySet<string> = new Set([
  // — Montar e editar orçamento/OS (o grosso do uso real) —
  "create_quote_from_items",
  "create_service_order",
  "get_service_order",
  "list_service_orders",
  "add_service_order_item",
  "add_service_to_order",
  "add_material_to_order",
  "add_kit_to_order",
  "edit_service_order_item",
  "remove_service_order_item",
  "apply_service_order_discount",
  "set_service_order_charges",
  "update_service_order_status",
  "update_service_order_notes",
  "update_quote_status",
  "duplicate_service_order",
  "get_service_order_margin",
  "get_os_profitability",
  "present_options",
  "size_dc_cable",

  // — Catálogo e cadastros (buscar, criar e corrigir) —
  "search_products",
  "search_products_batch",
  "search_services",
  "get_product_price_history",
  "create_product",
  "update_product",
  "search_clients",
  "create_client",
  "update_client",
  "search_vessels",
  "create_vessel",
  "update_vessel",
  "search_suppliers",
  "create_supplier",
  "list_reference_data",

  // — Levantamento antes de orçar —
  "check_needs_survey",
  "start_service_survey",
  "record_survey_answer",
  "assess_survey_confidence",
  "close_service_survey",
  "survey_material_list",

  // — Cotação a fornecedor, estoque e compras —
  "get_purchase_needs",
  "suggest_suppliers",
  "create_quote_request",
  "read_supplier_messages",
  "record_quote_response",
  "get_quote_comparison",
  "apply_quote_price",
  "list_pending_pos",
  "list_low_stock",
  "register_stock_entry",

  // — Financeiro do dia a dia (recebíveis, contas, cobrança, resultado) —
  "create_receivable",
  "create_payable",
  "update_receivable",
  "update_payable",
  "get_os_receivables",
  "list_overdue_receivables",
  "list_pending_collections",
  "list_payables_due",
  "get_delinquency_plan",
  "get_period_summary",
  "resultado_do_periodo",
  "get_top_clients",
  "listar_categorias_financeiras",

  // — Extrato, conciliação e propostas de lançamento —
  "sugerir_conciliacao",
  "listar_transacoes_pendentes",
  "analisar_extrato_e_propor_lancamentos",
  "listar_propostas_de_lancamento",
  "recusar_propostas_de_lancamento",
  "reclassificar_propostas_de_lancamento",
  "classificar_propostas_com_ia",
  "desfazer_propostas_ignoradas",
  "sugerir_regras_financeiras",
  "listar_regras_financeiras",
  "criar_regra_financeira",
  "listar_favorecidos",
  "cadastrar_favorecido",

  // — Agenda, tarefas e lembretes —
  "my_agenda",
  "list_team_agenda",
  "list_tasks",
  "create_task",
  "update_task",
  "complete_task",
  "schedule_service_order",
  "check_technician_availability",
  "list_technicians",
  "schedule_self_reminder",

  // — Técnico em campo: check-in/out, relato, hora, gasto e foto —
  "check_in_service_order",
  "check_out_service_order",
  "log_service_order_progress",
  "log_service_order_hours",
  "add_service_order_expense",
  "attach_photo_to_service_order",

  // — Roteiro de execução da OS —
  "get_service_order_route",
  "generate_service_order_route",
  "get_route_drafting_context",
  "save_drafted_route_steps",
  "add_service_order_step",
  "start_service_order_step",
  "complete_service_order_step",
  "skip_service_order_step",
  "block_service_order_step",

  // — Jornada da equipe —
  "registrar_jornada",
  "fechar_jornada",
  "minhas_horas",
  "apurar_pagamento",

  // — Fiscal: espelho e consulta (emitir é risco alto e entra sempre) —
  "preview_fiscal_note",
  "preview_fiscal_service_note",
  "list_fiscal_documents",

  // — Retrato e visão geral —
  "get_situation_overview",
  "get_open_loops",
  "get_client_360",
  "get_client_history",
  "get_vessel_history",
  "get_supplier_360",

  // — WhatsApp, contatos e mensagens —
  "list_unanswered_messages",
  "identify_contact",
  "link_whatsapp_lead_to_client",
  "mute_contact",
  "unmute_contact",
  "list_scheduled_whatsapp",
  "cancel_scheduled_whatsapp",
  "optimize_text",
  // Liberada em 26/09/2026 (migration 20260926173100) depois do teste real: "me manda o PDF
  // do ORÇ-86" deu "Tool desconhecida" em 25/09 porque o prompt ensinava e o perfil escondia.
  "send_document_pdf_to_self",

  // — "Deixar a IA acompanhar" (copiloto) —
  "criar_missao_acompanhamento",
  "listar_missoes_acompanhamento",
  "cancelar_missao_acompanhamento",

  // — Antigo SEMPRE_NO_PERFIL de agent.ts —
  // O perfil gravado no banco era editado à mão e ferramenta nova nascia fora dele — invisível
  // para o assistente, por mais que funcionasse. Foi o que aconteceu com
  // get_whatsapp_conversation: no ar desde 24/09/2026 e fora do perfil. As daqui são as que o
  // dono pediu para usar conversando (lançamentos, extrato, Caixa e fechamento do mês).
  "get_whatsapp_conversation",
  "buscar_lancamentos",
  "desfazer_aprovacao_de_lancamento",
  "casar_lancamento_com_extrato",
  "cadastrar_contraparte_do_extrato",
  "verificar_mes",
  "consultar_conta",
  "configurar_lancamento_automatico",
  "listar_lancados_sozinhos",
  "lancar_no_caixa",
  "ajustar_saldo_do_caixa",
  "anotar_transacao_do_banco",
  "gastos_por_categoria",

  // — Acrescentadas em 26/09/2026 (Frente C): o prompt ensina e o perfil escondia —
  // "DE QUEM É ESTE NÚMERO" e o portão de comunicação mandam vincular o número desconhecido
  // (destinatario_nao_identificado bloqueia a cobrança até isso ser feito).
  "link_contact_to_entity",
  // "CORRIGIR CADASTRO é rotina": o prompt manda update_supplier para telefone novo, nome usado
  // (display_name) e opt-out — e update_client/update_product/update_vessel já estavam aqui.
  "update_supplier",
  // CADASTRO FISCAL PENDENTE: o prompt mostra a tabela, pede UM "sim" e grava serviço a serviço.
  // Só pela rede, cada update_service virava uma pendência — 10 serviços, 10 "sim" a mais
  // (conferência de 26/09/2026). À vista, segue o risco low que declara e o "sim" do prompt basta.
  "update_service",
]);

/**
 * Ferramentas que o prompt CITA mas que ficam FORA do perfil de propósito — o modelo só as
 * alcança pela rede de segurança do executor (agent.ts) ou quando o usuário diz o nome.
 *
 * A REDE ALCANÇA SÓ O QUE ESTÁ AQUI. Tool fora do perfil e fora desta lista continua "Tool
 * desconhecida", mesmo que cargo e canal a liberem: vários `roles` são frouxos
 * (create_purchase_order não tem roles; get_technician_commissions abre para external_seller;
 * list_unidentified_contacts não tem roles), e o perfil era a única coisa que as mantinha longe
 * de técnico e vendedor. E mesmo daqui a rede só pega o que o cargo e o canal já liberaram
 * (params.tools): técnico continua sem as de dinheiro, e as de FORA_DO_WHATSAPP
 * (channel-scope.ts) continuam fora do WhatsApp.
 *
 * Como a rede trata cada uma, depois de conferir os argumentos contra o input_schema
 * (rodaDiretoPelaRede, abaixo): roda DIRETO só a de risco 'low' — o que a tool DECLARA e o que o
 * computeRisk calcula — que for LEITURA (pelo nome) ou ESCRITA DE SUGESTÃO/ANÁLISE listada em
 * ESCRITAS_VERIFICADAS_DA_REDE. Todo o resto — escrita de risco low fora dessa lista inclusive —
 * vira pendência de confirmação, sem autonomia. Para leitura, rodar direto é o que o prompt
 * promete (virar pendência cortava o turno, e no WhatsApp a resposta do modelo sumia).
 *
 * POR QUE ESCRITA PEDE CONFIRMAÇÃO PELA REDE, MESMO DE RISCO LOW: o modelo chama de memória do
 * prompt, sem ter visto a descrição — nem os limites que ela impõe ("só chame quando o usuário
 * mandar", "CONFIRME antes de gravar o fiscal"). O risco low foi dado pensando no modelo que VÊ
 * a tool; pela rede, o padrão é confirmar. À vista (no perfil, ou com o nome no pedido) a tool
 * segue o risco que declara. Conferência de 26/09/2026: review_entity_note rodando direto
 * deixava o modelo criar (remember_about_entity) e APROVAR a própria nota no mesmo turno —
 * furava o portão humano da memória; update_service muda preço e campo fiscal;
 * convert_external_quote_to_so cria OS, cliente e ativo.
 *
 * Por isso entrar aqui não abre escrita sem confirmação: o que decide é o prompt (ou uma tool
 * visível) ensinar a tool e o uso ser raro. Critério: nenhum uso na história da auditoria
 * (levantamentos de 26/09/2026) e uso raro por natureza. Se uma delas começar a aparecer em
 * eventos 'fora_do_perfil:<tool>' da auditoria, é sinal de que merece voltar ao perfil — mova
 * para PERFIL_OPERACAO.
 */
export const SO_PELA_REDE: ReadonlySet<string> = new Set([
  // — Memória por entidade: as notas APROVADAS já chegam prontas no contexto (ai-agent), então
  //   anotar/revisar/listar é gesto raro. Anotar roda direto (a nota nasce candidata); revisar
  //   (aprovar/rejeitar) pede confirmação pela rede — é o portão humano da memória —
  "remember_about_entity",
  "review_entity_note",
  "list_entity_notes",

  // — CRM proativo: listas frias que o dono pede de vez em quando, nunca no fluxo do dia —
  "list_maintenance_due",
  "list_inactive_clients",
  "list_untouched_assets",

  // — Leads externos (orçamentos que chegam de fora): zero uso até aqui —
  "list_external_quotes",
  "convert_external_quote_to_so",

  // — Fiscal além do espelho: detalhe de uma nota e o cadastro fiscal pendente, que só se
  //   completa na hora de emitir (list_fiscal_documents e os espelhos estão no perfil) —
  "get_fiscal_document",
  "list_pending_fiscal_products",

  // — Roteiro: manutenção da lista de passos (a execução do passo a passo está no perfil) —
  "remove_service_order_step",
  "reopen_service_order_step",
  "reorder_service_order_step",
  "review_ai_step", // também em FORA_DO_WHATSAPP: revisar rascunho é trabalho de tela

  // — Gasto de campo lançado errado: desfazer é raro (lançar está no perfil) —
  "remove_service_order_expense",

  // — Comunicação: métricas, histórico de toques e manejo da resposta que volta —
  "get_comms_log",
  "get_comms_metrics",
  "check_followup_cadence",
  // Escrita de análise, roda direto (ver ESCRITAS_VERIFICADAS_DA_REDE). Se o manejo de resposta
  // passar a ser usado no dia a dia, promova ao perfil.
  "interpret_customer_reply",
  "read_supplier_media",

  // — Cadastro estrutural e configuração do próprio agente (FORA_DO_WHATSAPP também) —
  "create_composed_product",
  "get_autonomy_settings",

  // — Plano de contas: quem ensina é o criar_regra_financeira (no perfil). Quando a categoria
  //   pedida não existe, ele devolve a dica "Use criar_categoria_de_despesa antes"; fora do
  //   alcance, o modelo obedecia e recebia "Tool desconhecida". É risco medium: pela rede vira
  //   pendência, como já era à vista. Cargos: admin e financeiro (CARGOS_FINANCEIRO) —
  "criar_categoria_de_despesa",
]);

/**
 * As únicas ESCRITAS que a rede deixa rodar direto, sem confirmação: escrita de SUGESTÃO ou
 * ANÁLISE — não muda registro de negócio, não mexe em dinheiro nem em preço, não manda nada
 * para fora e não aprova nada. Com o porquê de cada uma, lido no execute.
 *
 * O EXECUTOR CONSULTA esta lista (rodaDiretoPelaRede): escrita de SO_PELA_REDE que não está
 * aqui vira pendência, mesmo de risco low. O padrão é confirmar; acrescentar um nome aqui é a
 * exceção, e só depois de ler o execute.
 *
 * Saíram na conferência de 26/09/2026 e passaram a pedir confirmação pela rede:
 * review_entity_note (é o portão humano da memória: aprovando direto, o modelo criava e
 * aprovava a própria nota no mesmo turno), update_service (muda preço e campos fiscais),
 * convert_external_quote_to_so (cria OS, cliente e ativo) e, pelo mesmo critério,
 * reorder_service_order_step (reordena o roteiro da OS) e create_composed_product (cria produto
 * com preço no catálogo) — nenhuma das cinco com uso na auditoria até 26/09.
 */
export const ESCRITAS_VERIFICADAS_DA_REDE: Readonly<Record<string, string>> = {
  remember_about_entity:
    "sugestão: a nota nasce 'candidate' e só entra no contexto do agente depois que o dono aprova (review_entity_note, que pela rede pede confirmação)",
  interpret_customer_reply:
    "análise: classifica o texto; com entity_id, só marca responded_at/reply_intent no último toque de ai_comms_log",
};

/**
 * Leitura pelo nome (get_, list_, read_, check_, search_). O executor usa em rodaDiretoPelaRede;
 * perfil-operacao_test.ts confere que nenhuma "leitura pelo nome" de SO_PELA_REDE tem
 * insert/update/upsert/delete/rpc no execute — senão o nome estaria mentindo.
 */
export function ehLeituraPeloNome(nome: string): boolean {
  return /^(get_|list_|read_|check_|search_)/.test(nome);
}

/**
 * A regra da rede de segurança (agent.ts) para uma tool de SO_PELA_REDE chamada sem estar à
 * vista: roda DIRETO só se a tool declara risco 'low' E é leitura (pelo nome) ou escrita de
 * ESCRITAS_VERIFICADAS_DA_REDE. O executor ainda exige que o computeRisk calcule 'low' para a
 * chamada. false = vira pendência de confirmação.
 */
export function rodaDiretoPelaRede(tool: { name: string; risk: string }): boolean {
  return tool.risk === "low" &&
    (ehLeituraPeloNome(tool.name) || Object.prototype.hasOwnProperty.call(ESCRITAS_VERIFICADAS_DA_REDE, tool.name));
}
