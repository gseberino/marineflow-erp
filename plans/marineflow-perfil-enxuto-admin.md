# Perfil enxuto e fixo de ferramentas do administrador — proposta para aprovação

Data: 04/10/2026 · Pesquisa somente-leitura (código da main `f3febfa3` em `marineflow-erp--diario-itens` + consultas SELECT no banco de produção). Nada foi editado no repositório, nada foi publicado e nada foi gravado no banco.

## 0. Resumo em 6 linhas

- **Já existe um perfil, e ele está ligado**: `app_settings.ai_tool_profile = 'operacao'` desde 26/09. A lista mora em `_shared/ai/perfil-operacao.ts` (`PERFIL_OPERACAO`, 145 nomes) e vale para **todos os cargos**. Por isso o admin recebe hoje **166 ferramentas no painel (~35,6 mil tokens) e 156 no WhatsApp (~33,2 mil)**.
- **Uso real (60 dias)**: só o admin usa o assistente. Foram 761 chamadas de ferramenta, espalhadas por **66 ferramentas** (18 delas somam 80% das chamadas). Das 166 que o admin vê, **99 (60%) não foram chamadas nenhuma vez em 60 dias** e 88 nunca foram chamadas desde que a auditoria começou (10/07).
- **Proposta recomendada**: um perfil próprio do admin com **98 ferramentas + 1 ferramenta de acesso ("ferramenta_extra")**. O bloco cai para **~25,7 mil tokens (−28%) no painel e ~25,6 mil (−23%) no WhatsApp**. A variante mínima tem 75 ferramentas e fica em ~19,6 mil tokens (−45%).
- **Dinheiro**: no OpenRouter a economia seria de **~US$ 2–3/mês** sobre ~US$ 15/mês. Mas desde 03–04/10 o admin roda pelo **Claude Max** nos dois canais, e o OpenRouter ficou só como reserva. Por isso a economia real em dólar fica perto de zero. O ganho de verdade está no Max: cada turno de WhatsApp lê ~38–50 mil tokens a menos da cota da assinatura, que é a mesma que o dono usa no Claude Code. As respostas também ficam mais rápidas quando o cache expira.
- **Achado que pesa na decisão**: no Claude Max, a "rede de segurança" (`SO_PELA_REDE`) provavelmente **não alcança nada**. O `erp-mcp` lista ao Claude Code só as ferramentas visíveis, e o Claude Code não chama ferramenta que não foi listada. Por isso o perfil enxuto só é seguro com uma ferramenta visível que despache as escondidas. Isso precisa ser confirmado com um teste.
- **Nenhuma mudança para o técnico**: o perfil novo vale só para `userRole = 'admin'`. Os outros cargos continuam com o `PERFIL_OPERACAO` de hoje.

---

## 1. O que o admin recebe HOJE e quanto custa

### Como é montado (código)
1. Filtro por **cargo**: `allTools.filter(t => !t.roles || t.roles.includes(role))`, em `ai-agent/index.ts:627` (WhatsApp) e `:1189` (painel).
2. Filtro por **canal**: `filtrarPorCanal` (`channel-scope.ts`) tira 22 nomes do WhatsApp (`FORA_DO_WHATSAPP`). Para o admin isso dá 10 a menos.
3. **Perfil**: `aplicarPerfilDeTools` (`agent.ts:528`). Com `ai_tool_profile='operacao'`, entram `PERFIL_OPERACAO`, **todas as de risco alto** e qualquer ferramenta cujo nome apareça escrito no pedido.
4. **Rede de segurança**: `prepararFerramentasDoTurno` (`agent.ts:622`) e `executarChamadaDeTool` (`agent.ts:656`). Uma ferramenta de `SO_PELA_REDE` (23 nomes) chamada sem estar visível tem os argumentos conferidos contra o `input_schema` e, se errados, devolve o esquema ao modelo. Leitura de risco baixo roda direto; o resto vira pendência de confirmação. Cada uso é auditado como `fora_do_perfil:<tool>`.
5. **Aprovação de pendência**: usa o `toolsByName` global (`ai-agent/index.ts:323`). Por isso aprovar no sino ou com "sim <PIN>" **não depende** de a ferramenta estar visível.
6. **Claude Max** (`ai_provedor_painel` e `ai_provedor_whatsapp` = `claude_max` desde 03–04/10): o job leva os nomes `visiveis` e `rede` (`max/claude-max.ts:170`). O `erp-mcp` revalida (`max/ferramentas-do-job.ts`) e, em `tools/list`, **lista só as visíveis** (`erp-mcp/index.ts:79`). O gateway roda com `ENABLE_TOOL_SEARCH=false` (`hbr-ai-gateway/src/providers/claude-shared.ts:40`), então o bloco inteiro também vai em toda chamada.

### Números (medidos na serialização, não no .ts)
**Método.** O script importa `allTools` do repositório e aplica os mesmos filtros de cargo, canal e perfil (sem nome escrito no pedido). Depois faz `JSON.stringify` da lista no formato que chega à Anthropic, `[{name, description, input_schema}]`, e calcula **tokens ≈ caracteres ÷ 3,6**. O formato do OpenRouter (`{type:"function", function:{name, description, parameters}}`, em `anthropic.ts:157`) dá ~4% a mais de caracteres. Scripts: `mede.ts`, `cruza.ts`, `final.ts` nesta pasta.

| admin | ferramentas | caracteres (formato Anthropic) | tokens (÷3,6) | sem perfil (se desligar) |
|---|---:|---:|---:|---|
| Painel | **166** (145 do perfil + 21 de risco alto) | 128.340 | **35.650** | 222 / 44.006 tok |
| WhatsApp | **156** | 119.632 | **33.231** | 200 / 39.739 tok |

Para comparar: o bloco estável do prompt (`prompt.ts`) tem 55.800 caracteres (~15.500 tok).

**Calibração (o ÷3,6 subestima).** O cabeçalho de `channel-scope.ts` registra uma medição real de ~256 tokens por ferramenta (48 mil para 188 ferramentas). O ÷3,6 dá ~199 por ferramenta. O motivo é que a Anthropic embrulha as ferramentas num texto próprio e o português gera mais tokens por caractere. **O valor real deve ser ~25–30% maior.** Isso bate com o menor `tokens_in` por chamada visto depois de 26/09: 77.966 no painel e 74.146 no WhatsApp (ferramentas + prompt + conversa). Todas as economias abaixo crescem na mesma proporção.

---

## 2. Uso real nos últimos 60 dias (05/08 a 04/10)

**Fonte**: `ai_operator_audit`, eventos `tool:<nome>` (executou direto) + `pending_action:<nome>` (virou pendência). Os dois são chamadas feitas pelo modelo. Canal vem de `payload.channel`, cargo de `app_users.role`.

- **761 chamadas**: 546 no painel e 215 no WhatsApp; 714 diretas e 47 que viraram pendência. **760 do admin** e 1 de técnico (`my_agenda`, 19/09).
- **67 ferramentas distintas** (66 do admin): 47 no painel e 46 no WhatsApp. **18 ferramentas somam 80% das chamadas**, quase todas de montar orçamento ou OS.
- **Nunca chamadas em 60 dias**: 99 das 166 que o admin vê no painel (60%) e 89 das 156 do WhatsApp. Somando todas as 222 ferramentas, são 155 (70%). **88 das 166 visíveis nunca foram chamadas** desde o início da auditoria (10/07).
- **A rede de segurança nunca disparou**: zero eventos `fora_do_perfil:*` na história inteira. "Tool desconhecida" apareceu 1 vez (26/09, WhatsApp).
- Nomes antigos que ainda aparecem na auditoria e não existem mais: `list_agenda`, `create_agenda_task`.

### As 66 ferramentas usadas pelo admin (grupo A: ficam por uso real)

| tool | chamadas 60d | painel | WhatsApp | risco | tokens |
|---|---:|---:|---:|---|---:|
| remove_service_order_item | 84 | 75 | 9 | low | 213 |
| add_service_order_item | 71 | 60 | 11 | low | 170 |
| create_product | 68 | 59 | 9 | low | 319 |
| get_service_order | 52 | 37 | 15 | low | 53 |
| search_products | 51 | 45 | 6 | low | 57 |
| add_service_to_order | 48 | 33 | 15 | low | 160 |
| get_product_price_history | 40 | 40 | 0 | low | 191 |
| edit_service_order_item | 32 | 18 | 14 | low | 356 |
| search_clients | 27 | 10 | 17 | low | 66 |
| list_service_orders | 24 | 9 | 15 | low | 423 |
| size_dc_cable | 24 | 23 | 1 | low | 343 |
| create_quote_from_items | 19 | 12 | 7 | low | 681 |
| search_vessels | 19 | 7 | 12 | low | 64 |
| add_material_to_order | 15 | 7 | 8 | low | 306 |
| registrar_diaria | 12 | 0 | 12 | medium | 545 |
| cancel_service_order | 11 | 11 | 0 | high | 87 |
| update_product | 11 | 6 | 5 | low | 372 |
| search_products_batch | 10 | 8 | 2 | low | 218 |
| create_service_order | 9 | 3 | 6 | low | 460 |
| criar_regra_financeira | 9 | 9 | 0 | medium | 953 |
| record_survey_answer | 9 | 9 | 0 | low | 209 |
| assess_survey_confidence | 7 | 7 | 0 | low | 239 |
| survey_material_list | 7 | 7 | 0 | low | 115 |
| close_service_survey | 6 | 6 | 0 | low | 97 |
| gastos_por_categoria | 6 | 0 | 6 | low | 412 |
| register_payment | 6 | 0 | 6 | high | 156 |
| search_suppliers | 6 | 4 | 2 | low | 154 |
| consultar_freelancer | 4 | 0 | 4 | low | 150 |
| create_vessel | 4 | 3 | 1 | low | 151 |
| send_service_order_link | 4 | 1 | 3 | high | 406 |
| update_service_order_notes | 4 | 4 | 0 | low | 269 |
| create_client | 3 | 1 | 2 | low | 401 |
| create_quote_request | 3 | 3 | 0 | low | 362 |
| get_client_360 | 3 | 2 | 1 | low | 172 |
| get_whatsapp_conversation | 3 | 0 | 3 | low | 429 |
| list_reference_data | 3 | 2 | 1 | low | 173 |
| present_options | 3 | 3 | 0 | low | 298 |
| set_service_order_charges | 3 | 2 | 1 | low | 241 |
| check_needs_survey | 2 | 1 | 1 | low | 231 |
| get_os_receivables | 2 | 2 | 0 | low | 99 |
| identify_contact | 2 | 0 | 2 | low | 164 |
| lancar_no_caixa | 2 | 0 | 2 | medium | 421 |
| list_unanswered_messages | 2 | 0 | 2 | low | 210 |
| listar_categorias_financeiras | 2 | 2 | 0 | low | 66 |
| log_service_order_progress | 2 | 2 | 0 | low | 248 |
| search_services | 2 | 1 | 1 | low | 64 |
| sugerir_conciliacao | 2 | 2 | 0 | low | 122 |
| suggest_suppliers | 2 | 2 | 0 | low | 125 |
| update_client | 2 | 1 | 1 | low | 522 |
| update_vessel | 2 | 2 | 0 | low | 364 |
| add_kit_to_order | 1 | 1 | 0 | low | 164 |
| anotar_transacao_do_banco | 1 | 0 | 1 | medium | 374 |
| buscar_lancamentos | 1 | 0 | 1 | low | 330 |
| create_supplier | 1 | 0 | 1 | low | 84 |
| duplicate_service_order | 1 | 0 | 1 | medium | 184 |
| get_client_history | 1 | 0 | 1 | low | 51 |
| get_delinquency_plan | 1 | 0 | 1 | low | 159 |
| get_period_summary | 1 | 0 | 1 | low | 284 |
| get_purchase_needs | 1 | 1 | 0 | low | 218 |
| list_overdue_receivables | 1 | 0 | 1 | low | 90 |
| listar_transacoes_pendentes | 1 | 0 | 1 | low | 130 |
| read_supplier_messages | 1 | 0 | 1 | low | 224 |
| send_document_pdf_to_self | 1 | 0 | 1 | low | 211 |
| send_supplier_quote_request | 1 | 1 | 0 | high | 334 |
| start_service_survey | 1 | 1 | 0 | low | 241 |
| update_service_order_status | 1 | 1 | 0 | low | 269 |

(tokens = tamanho de cada ferramenta no bloco, ÷3,6.)

---

## 3. A proposta

### Critério (fixo, por cargo e canal; nunca por mensagem)
O conjunto continua **estável**: uma lista fixa para o admin (e outra, a de hoje, para os demais cargos). O filtro de canal continua por cima. Nada de `ai_intent_router`. A lista muda só no deploy, e cada deploy custa **uma** gravação de cache.

Uma ferramenta **fica** se cumprir pelo menos uma destas condições:
- **A. Uso real**: ≥1 chamada do admin em 60 dias (66 ferramentas, tabela acima). Com 761 chamadas no período, cortar em ≥2 seria ruído. Várias das usadas 1 vez são recursos novos (01–04/10).
- **B. Crítica, ou rara mas precisa estar à mão** (32 ferramentas). Ação em produção que o dono pediu para fazer conversando; ação que fecha um fluxo que já tem uso; ou escrita de risco baixo que, **pela rede, passaria a pedir confirmação** e atrapalharia um pedido comum. Quando uma ferramenta fica visível, ela segue o risco que declara.

| grupo | tools | tokens | por que fica |
|---|---|---:|---|
| fiscal | preview_fiscal_note, preview_fiscal_service_note, emit_fiscal_note, emit_fiscal_service_note, list_fiscal_documents | 1003 | Emissão fiscal está EM PRODUÇÃO; "a nota saiu?" vem pelo WhatsApp; espelho → emitir é o fluxo que o prompt manda (L245-263) |
| dinheiro | cancelar_lancamento, desfazer_aprovacao_de_lancamento, aplicar_pix_em_contas, desfazer_aplicacao_de_pix, casar_lancamento_com_extrato, conciliar_transacao, create_receivable, create_payable, update_receivable, update_payable | 2778 | Corrigir/desfazer dinheiro pedido pelo dono para usar conversando (Financeiro Confiável, Pix várias contas F2 no ar 02/10); conciliar_transacao fecha o fluxo de sugerir_conciliacao (usada) |
| funil | update_quote_status, approve_quote_full, register_deposit_and_convert, apply_service_order_discount | 823 | Funil do orçamento e sinal (no ar 03/10); desconto custa 71 tok e é parte do "montar orçamento" (uso real em julho) |
| comunicacao | send_whatsapp_message, schedule_whatsapp_message, send_collection_reminder, link_contact_to_entity | 679 | Portão de comunicação: fora_de_horario → agendar (dono trabalha à noite); destinatario_nao_identificado → vincular; cobrança |
| cadastro | update_service, update_supplier, cadastrar_freelancer | 1282 | update_service/update_supplier entraram no perfil em 26/09 de propósito (pela rede, cada serviço do cadastro fiscal virava um "sim"); cadastrar_freelancer pedido pelo dono em 01/10 |
| cotacao | record_quote_response, get_quote_comparison, apply_quote_price | 701 | Fecham o ciclo de cotação que já tem uso (create_quote_request 3x); pela rede, cada item respondido viraria uma confirmação |
| agenda | create_task, schedule_self_reminder, my_agenda | 988 | "me lembra de..." e "minha agenda" são pedidos de linguagem natural; pela rede, criar tarefa viraria confirmação |

**Total recomendado: 98 ferramentas + `ferramenta_extra` = 99.** Hoje o admin vê 166 no painel e 156 no WhatsApp.

### O que SAI do que o admin vê hoje (68 no painel; 58 no WhatsApp, onde 10 já estavam fora)
Agrupado por como continua alcançável:

| tipo | ferramentas | pela rede/`ferramenta_extra` |
|---|---|---|
| risco alto (8) | adjust_inventory, aprovar_propostas_de_lancamento, fechar_mes, followup_send_touch, receive_purchase_order, schedule_status_post, send_bulk_collection_reminders, set_tool_autonomy | vira pendência: **o mesmo comportamento de hoje** (risco alto sempre pede "sim"); só a autonomia concedida não vale pela rede |
| risco médio (10) | ajustar_lancamento_ao_valor_do_banco, ajustar_saldo_do_caixa, analisar_extrato_e_propor_lancamentos, cadastrar_contraparte_do_extrato, cadastrar_favorecido, cancelar/criar_missao_acompanhamento, configurar_lancamento_automatico, desfazer_propostas_ignoradas, link_whatsapp_lead_to_client | vira pendência: o mesmo de hoje |
| leitura em inglês (18) | check_technician_availability, get_open_loops, get_os_profitability, get_route_drafting_context, get_service_order_margin, get_service_order_route, get_situation_overview, get_supplier_360, get_top_clients, get_vessel_history, list_low_stock, list_payables_due, list_pending_collections, list_pending_pos, list_scheduled_whatsapp, list_tasks, list_team_agenda, list_technicians | roda direto (`rodaDiretoPelaRede`) |
| leitura em português (8) | consultar_conta, listar_favorecidos, listar_lancados_sozinhos, listar_missoes_acompanhamento, listar_propostas_de_lancamento, listar_regras_financeiras, resultado_do_periodo, verificar_mes | **hoje viraria pendência**: `ehLeituraPeloNome` só reconhece `get_/list_/read_/check_/search_`. Precisa do ajuste da seção 5 |
| escrita de risco baixo (24) | add_service_order_expense, log_service_order_hours, check_in/check_out_service_order, attach_photo_to_service_order, add/start/complete/skip/block_service_order_step, generate_service_order_route, save_drafted_route_steps, schedule_service_order, complete_task, update_task, cancel_scheduled_whatsapp, mute/unmute_contact, optimize_text, register_stock_entry, classificar/reclassificar/recusar_propostas_de_lancamento, sugerir_regras_financeiras | **passa a pedir confirmação** (regra de 26/09: o modelo chama sem ter lido a descrição). Para o admin isso é aceitável porque nenhuma teve uso. Atenção: `check_in_`/`check_out_` começam com `check_` e seriam tratadas como LEITURA (rodariam direto). Precisa do ajuste da seção 5 |

Os demais cargos não mudam. A lista completa por ferramenta, com tamanho, risco, uso e linhas do prompt, está em `cruza.json` nesta pasta.

### Como o que sai continua alcançável (o que o código já tem, mais uma peça)
1. **O que já existe e fica igual**: a **rede de segurança** (`executarChamadaDeTool`: confere argumentos, devolve o `input_schema` quando erram, leitura roda direto, escrita vira pendência, audita `fora_do_perfil:<tool>`); o **nome escrito no pedido** ("use a list_low_stock") põe a ferramenta à vista naquele turno, que perde o cache só naquela vez porque é raro; e a **aprovação** que executa pelo `toolsByName` global.
2. **Ampliar a rede só para o admin**: hoje ela alcança só os 23 nomes de `SO_PELA_REDE`, de propósito. Vários `roles` são frouxos, e o perfil era o que afastava técnico e vendedor dessas ferramentas. Para o admin esse motivo não existe, porque o cargo libera tudo. Então, **para o admin, a rede = tudo que cargo e canal liberam e que não está no perfil** (124 no painel, 102 no WhatsApp). Para os outros cargos ela continua sendo `SO_PELA_REDE`.
3. **A peça nova, necessária por causa do Claude Max: `ferramenta_extra`**, uma ferramenta fixa e visível com `{nome (enum com os nomes da rede), argumentos, descrever}`.
   - `descrever=true` devolve `description` + `input_schema` sem executar, para o modelo ler os limites antes de uma escrita. Isso responde à preocupação que motivou a regra de 26/09.
   - Sem `descrever`, ela redespacha `{nome, argumentos}` pelo **mesmo** caminho da rede: mesma validação, mesma pendência e mesma auditoria. A pendência é gravada com o nome real, então o "sim" executa a ferramenta certa.
   - Custa ~0,9–1,2 mil tokens (o enum funciona como catálogo de nomes). Como é fixa por cargo e canal, **não quebra o cache**, e o resultado dela entra na conversa, não no bloco de ferramentas.
   - **Por que é necessária**: no Max, o Claude Code só conhece o que o `tools/list` do `erp-mcp` devolve (as visíveis). Chamar diretamente um nome escondido não chega ao `erp-mcp`. **Hoje** isso já deixa as 23 de `SO_PELA_REDE` fora de alcance no Max. Hipótese forte, confirmar com um teste: pedir pelo WhatsApp algo que só `list_external_quotes` resolve.

### Economia estimada

| variante | painel: tools / tokens | WhatsApp: tools / tokens | economia por chamada |
|---|---|---|---|
| hoje | 166 / 35.650 | 156 / 33.231 | — |
| **recomendada** (A + B + extra) | 99 / **25.709** | 99 / **25.556** | −9.941 (−28%) painel · −7.675 (−23%) WhatsApp |
| mínima (A + fiscal + conciliar_transacao + update_service/update_supplier + extra) | 75 / 19.631 | 75 / 19.478 | −16.019 (−45%) · −13.753 (−41%) |

Tokens ÷3,6. Pela calibração da seção 1, os valores reais devem ser ~25–30% maiores.

**Em US$ (OpenRouter).**
- **Base**: `v_ai_custo_diario` dos últimos 60 dias. Foram 534 chamadas ao modelo (307 no painel, 227 no WhatsApp), ≈267 por mês, e **US$ 30,32 no total (≈US$ 15/mês)**. Preço vigente na view: US$ 3,00/M de entrada (desde 01/09), leitura de cache a 10% (US$ 0,30/M) e gravação a +25% (US$ 3,75/M). **83,5% das chamadas leram cache**; 16,5% (88) não leram.
- **Preço médio de um token do bloco de ferramentas**: o bloco é o começo do prefixo, então é lido do cache sempre que há cache e regravado quando não há. Fica 0,835 × 0,30 + 0,165 × 3,75 ≈ **US$ 0,87/M**.
- **Recomendada**: média ponderada de 8,98 mil tokens a menos por chamada × US$ 0,87/M ≈ US$ 0,0078 por chamada, ou **≈ US$ 2,1/mês (≈ US$ 2,7 calibrado; ~14–18% da conta)**. Se todas as chamadas lessem do cache, seria só US$ 0,72/mês.
- **Mínima**: 15 mil tokens a menos por chamada, **≈ US$ 3,5/mês (≈ US$ 4,5 calibrado)**.
- **Porém**: desde 03–04/10 o admin, que é o único usuário real, vai pelo **Claude Max** nos dois canais, e o OpenRouter é só reserva (`ai_whatsapp_max_reserva = on`). **A economia em dólar a partir de agora é de ~US$ 0–1/mês.**

**No Claude Max, onde o ganho de fato aparece:**
- Nos 8 turnos de 04/10 (`ai_jobs.usage`), cada turno fez 2–10 chamadas internas (média de 5 no WhatsApp) e leu **135 a 486 mil tokens do cache por turno**. Cada chamada interna relê o bloco de ferramentas.
- Com a recomendada, um turno de WhatsApp lê ~38 mil tokens a menos (~50 mil calibrado), **~10–25% a menos por turno** contra as janelas de 5 horas e de 7 dias. A de 7 dias estava em 23–29%, e essa cota é a mesma que o dono usa no Claude Code.
- Quando o cache expira, a gravação também fica menor: os jobs do painel gravaram 84–90 mil tokens de cache cada. Isso deixa a primeira resposta mais rápida.
- O `cost_usd_estimate` do SDK (US$ 0,14–0,42 por turno) é **equivalente de API**, não é cobrado.

---

## 4. Riscos

### 4.1 Ferramentas que o prompt ENSINA e que sairiam do perfil do admin (`_shared/ai/prompt.ts`)
O teste `prompt-ferramentas_test.ts` exige que toda ferramenta citada pelo prompt esteja ao alcance. Pela proposta, todas ficam alcançáveis pela rede do admin e por `ferramenta_extra`. **Nenhuma linha do prompt precisa ser apagada**, mas o modelo deixa de ver a descrição e o esquema delas.

| ferramenta | risco | linhas do prompt.ts | o que muda para o admin |
|---|---|---|---|
| list_team_agenda | baixo (leitura) | 78 | nada (leitura roda direto) |
| check_technician_availability | baixo (leitura) | 81, 358, 359 | nada |
| schedule_service_order | baixo (escrita) | 205 | agendar a OS passa a pedir "sim" |
| get_situation_overview | baixo (leitura) | 230 | nada ("como estão as coisas?") |
| list_pending_collections | baixo (leitura) | 239, 242 | nada |
| send_bulk_collection_reminders | alto | 242 | nada (já pedia "sim") |
| add_service_order_expense | baixo (escrita) | 288, 309 | "gastei R$ 80 de gasolina" passa a pedir "sim" |
| log_service_order_hours | baixo (escrita) | 289, 290, 309 | "trabalhei 2h" passa a pedir "sim" |
| cadastrar_favorecido | médio | 299 | nada (já pedia "sim") |
| get_supplier_360 | baixo (leitura) | 318 | nada |
| set_tool_autonomy | alto | 345, 346 | nada (já pedia "sim" + PIN) |
| check_in_service_order / check_out_service_order | baixo (escrita) | 354 / 355 | **rodariam direto pela rede** (o nome começa com `check_`): corrigir |
| attach_photo_to_service_order | baixo (escrita) | 357 | passa a pedir "sim" |
| get_service_order_route | baixo (leitura) | 363, 364, 371 | nada |
| complete/block/start/skip/add_service_order_step | baixo (escrita) | 365 / 366 / 367 / 368 / 369 | passam a pedir "sim" |
| generate_service_order_route | baixo (escrita) | 372 | passa a pedir "sim" |
| cancel_scheduled_whatsapp / list_scheduled_whatsapp | baixo | 427 | cancelar passa a pedir "sim"; listar nada |

Além disso, as linhas **46–47** do prompt dizem que ações de back-office "executam direto". Para as escritas de risco baixo que saem, isso deixa de ser verdade **para o admin**. Vale uma frase no parágrafo novo (seção 5) avisando que ferramenta usada por `ferramenta_extra` pode pedir confirmação.

### 4.2 Fluxos do técnico no WhatsApp
**O técnico não muda**: a proposta escolhe o perfil por `toolCtx.userRole === 'admin'`. O técnico continua com as 63 ferramentas que recebe hoje no WhatsApp: check-in/out, relato, foto, roteiro passo a passo, agenda, levantamento e tarefas (prompt L352–372).

O risco real é de **implementação**: se o perfil do admin vazar para outros cargos, o técnico perde 28 dessas ferramentas de campo. Mitigação: um teste que fotografa a lista de nomes do técnico no WhatsApp e quebra se ela mudar.

Hoje o técnico praticamente não usa o assistente (1 chamada em 60 dias), então qualquer problema ali demoraria a aparecer.

### 4.3 Outros
- **Gasto e hora do próprio dono no campo** (`add_service_order_expense`, `log_service_order_hours`): zero uso em 60 dias, mas a "paridade tela de OS ↔ assistente" investiu nelas. Se o dono usa isso no barco, elas devem ficar no perfil (+715 tok). **Decisão do dono.**
- **Ciclo de cotação**: o projeto registra que "o dono nunca usou compras". Se a cotação a fornecedor também não for usada, dá para tirar o ciclo inteiro (create_quote_request, send_supplier_quote_request, suggest_suppliers, read_supplier_messages, record_quote_response, get_quote_comparison, apply_quote_price: ~1,9 mil tok). **Decisão do dono.**
- **A rede nunca foi exercitada em produção** (zero `fora_do_perfil`). O primeiro uso real vai ser depois desta mudança, então é preciso olhar a auditoria na primeira semana.
- **Cache**: o deploy muda o prefixo uma vez (uma gravação por canal). O `ai_tool_profile` é relido a cada 5 minutos, então dá para ter um botão de desligar sem deploy (seção 5).
- **Leituras com nome em português**: sem o ajuste de `ehLeituraPeloNome`, oito leituras (`listar_*`, `consultar_conta`, `verificar_mes`, `resultado_do_periodo`) virariam pendência, o que é absurdo para uma consulta.

---

## 5. O que mudaria no código (sem implementar)

1. **`_shared/ai/perfil-operacao.ts`**
   - Novo `PERFIL_ADMIN` com os 98 nomes e o porquê de cada grupo.
   - Ajustar `ehLeituraPeloNome`: aceitar `listar_|consultar_|verificar_|buscar_|resultado_` e **excluir** `check_in_|check_out_`. Melhor ainda: uma lista explícita de leituras, como já existe `ESCRITAS_VERIFICADAS_DA_REDE`.
2. **`_shared/ai/agent.ts`**
   - `aplicarPerfilDeTools`: escolher o perfil por `params.toolCtx.userRole`. Para o admin, só `PERFIL_ADMIN`, sem o "todo risco alto entra". Para os demais, como hoje.
   - Ler um novo valor do setting (ex.: `ai_tool_profile = 'admin_enxuto'`) para ligar e desligar sem deploy. Voltar a `'operacao'` restaura o comportamento de hoje.
   - `prepararFerramentasDoTurno`: para o admin, `alcancaveisPelaRede` = `params.tools` menos as visíveis. Também monta a `ferramenta_extra`, com o enum ordenado dos nomes da rede, e a inclui em `tools`.
   - `executarChamadaDeTool`: tratar `ferramenta_extra`. Com `descrever`, devolve a descrição e o esquema. Sem ele, redespacha `{name: nome, input: argumentos}` pelo caminho `foraDoPerfil` que já existe.
3. **`_shared/ai/max/ferramentas-do-job.ts`**: aceitar a rede do admin (hoje exige `SO_PELA_REDE.has(n)`) e remontar a `ferramenta_extra`. O **`erp-mcp/index.ts`** passa a listá-la pelo `toolsByName`.
4. **`_shared/ai/prompt.ts`**: um parágrafo no bloco estável, logo após a L50 ("Não peça IDs…"). Algo como: "Se a ferramenta que este texto manda usar não estiver na sua lista, use `ferramenta_extra` com o nome dela (`descrever=true` antes de uma escrita); por ali, escrita pode pedir confirmação." Nenhuma linha sai.
5. **Testes**:
   - `prompt-ferramentas_test.ts`: versão da regra 2 para o admin (citada ⇒ `PERFIL_ADMIN` ∪ rede do admin). Os limites de sanidade `visiveis.length > 100` passam a valer só para o perfil de operação.
   - `perfil-operacao_test.ts`: a checagem "leitura pelo nome não grava" estendida à rede do admin. É ela que pega `check_in`/`check_out`.
   - Teste novo que fotografa os nomes do técnico no WhatsApp.
   - `ferramentas-do-job_test.ts` e um teste da `ferramenta_extra` (descrever, despacho, pendência com o nome real).
6. **Deploy**: `ai-agent` e `erp-mcp` (os dois importam `_shared`). No banco, só o valor do setting. Depois do deploy, acompanhar `ai_operator_audit` com `event_type like 'fora_do_perfil:%'` (`payload.desfecho`). A ferramenta que aparecer toda semana volta para `PERFIL_ADMIN`.

### Decisões para o dono
1. Variante **recomendada** (99 ferramentas, −28%) ou **mínima** (75, −45%, com mais "sim" e mais ida pela rede)?
2. Gasto e hora de campo (`add_service_order_expense`, `log_service_order_hours`): ficam à vista (+715 tok) ou podem pedir "sim"?
3. Ciclo de cotação a fornecedor: fica (~1,9 mil tok) ou sai inteiro?

---
Arquivos de apoio nesta pasta: `medida.json` (medição por cargo e canal), `cruza.json` (por ferramenta: tamanho, risco, uso, linhas do prompt), `final.json` (variantes), `q6.rows` (uso por ferramenta), `q*.sql` (consultas, todas SELECT).
