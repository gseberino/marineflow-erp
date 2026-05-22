# MarineFlow AI Operator — Macro Ciclo 1

> Fundação técnica do MarineFlow AI Operator: persistência, gate determinístico
> de aprovação, integração no assistente interno do ERP e bridge passiva do
> WhatsApp. Branch: `feat/marineflow-ai-operator-macro-cycle-1`.

## Identidade e separação de projetos

O **MarineFlow AI Operator** é uma inteligência operacional integrada
exclusivamente ao MarineFlow ERP. Atua sobre clientes, embarcações/motorhomes,
produtos, serviços, orçamentos, OS, agenda, WhatsApp operacional, etc.

**Não confundir com:**
- HBR Operator / HBR Agent Core — projeto separado, não tocado nesta entrega.
- HBR Intelligence / Evolution API / n8n — não tocados nesta entrega; serão
  considerados como possíveis canais futuros via adapter.

## O que foi implementado

### 1. Schema persistente (migrations aditivas)

`supabase/migrations/20260522190000_ai_operator_foundation.sql` cria:

| Tabela | Função |
| --- | --- |
| `ai_operator_sessions` | Sessões de conversa cross-channel (web/whatsapp). |
| `ai_operator_messages` | Histórico com tool calls e anexos. |
| `ai_operator_drafts` | Rascunhos operacionais (quote/diagnosis/service_plan/agenda_proposal/response_suggestion/note). |
| `ai_operator_draft_items` | Itens do rascunho (service/product/product_to_quote/displacement/engineering/pending_question/risk/reference). |
| `ai_operator_pending_actions` | **Gate determinístico** — ações sensíveis ficam aqui em `pending` até aprovação. |
| `ai_operator_audit` | Auditoria append-only de todas as decisões do operador. |
| `ai_operator_memory_notes` | Memória técnica reutilizável por embarcação/cliente. |
| `ai_operator_channel_events` | Fila de eventos brutos de canal (Z-API hoje; Evolution/n8n no futuro). |

`supabase/migrations/20260522190100_ai_operator_whatsapp_bridge.sql` adiciona
um trigger AFTER INSERT em `whatsapp_messages` que enfileira mensagens
**inbound** em `ai_operator_channel_events` sem tocar no edge function
`whatsapp-webhook`.

**RLS:** todas as tabelas têm RLS habilitado. SELECT/INSERT/UPDATE liberados
para usuários autenticados ativos em `app_users`. `ai_operator_audit` é
append-only (sem políticas de UPDATE/DELETE para `authenticated`).

**Aplicação:** as duas migrations são **aditivas e seguras**. Devem ser
aplicadas em staging (`okurngvcodmljjicopdp`) pelo fluxo normal do projeto
(supabase CLI ou pipeline). Esta sessão não leu `.env*` nem aplicou as
migrations remotamente — preservando a regra de não expor segredos.

### 2. Edge Functions

#### `supabase/functions/ai-operator-core/`

Novo núcleo seguro. Não substitui o `ai-agent` legacy.

- `risk.ts` — classificação determinística de risco. SAFE_ACTIONS é um set
  fechado (leitura + operações internas). Tudo que não estiver em SAFE_ACTIONS
  e não tiver entrada no `RISK_MAP` cai em `high` por padrão (**fail-closed**).
- `tools.ts` — somente tools SEGURAS são expostas ao modelo: leitura
  (search_clients, search_vessels, search_products, search_services,
  get_vessel_history, list_technicians) + operações internas (create_draft,
  add_draft_item, ask_pending_question, register_memory_note, propose_action).
- `prompt.ts` — system prompt focado em interpretar demandas e produzir
  rascunhos estruturados (sem fechar preço, sem enviar ao cliente).
- `index.ts` — handler HTTP:
  - Cria/recupera sessão.
  - Persiste cada mensagem em `ai_operator_messages`.
  - Loop de tool calling com gate determinístico:
    - Se a tool retornada pelo modelo for SAFE → executa.
    - Se for `propose_action` → cria `ai_operator_pending_actions` em
      status `pending` e devolve para o frontend mostrar card de aprovação.
    - Se for qualquer outra tool sensível chamada diretamente → **BLOQUEIA**
      via `tool_call_blocked` na auditoria e devolve mensagem ao modelo
      orientando a usar `propose_action`. **Nenhuma escrita sensível ocorre.**
  - Endpoints adicionais: `approve_action`, `reject_action`.

> **Importante:** aprovação registra intenção e auditoria; execução real das
> ações sensíveis (envio WhatsApp, criação de OS oficial, etc.) **não é
> disparada automaticamente** neste ciclo. Isso é intencional — evita
> regressão em fluxos sensíveis enquanto a integração definitiva é validada.

#### `supabase/functions/ai-operator-channel-intake/`

Adapter genérico de canal. Aceita envelope normalizado
(channel/provider/external_event_id/payload) e enfileira em
`ai_operator_channel_events`. Fechada por `AI_OPERATOR_INTAKE_TOKEN`
(secret). Permite que Evolution API/n8n futuramente alimentem o operador
**sem reescrever** o núcleo. Dedupe por `(provider, external_event_id)`.

### 3. Frontend

- `src/hooks/use-ai-operator.ts` — novo hook que conversa com
  `ai-operator-core`. Mantém `session_id`, expõe `display`,
  `activeDraftId`, `activePendingActionId`, `sendMessage`, `approveAction`,
  `rejectAction`, `reset`.
- `src/components/ai/AIOperatorDraftCard.tsx` — exibe rascunho criado pelo
  operador (kind, summary, itens, perguntas pendentes, próximos passos,
  hipóteses), carregando direto de `ai_operator_drafts` e
  `ai_operator_draft_items` via supabase-js (RLS aplicada).
- `src/components/ai/AIOperatorPendingActionCard.tsx` — exibe ação sensível
  com badge de risco e botões Aprovar/Rejeitar.
- `src/components/ai/AIAgentWidget.tsx` — botão toggle “Bot” no header ativa
  **Modo Operador (beta)**. No modo legado, o widget continua idêntico.

### 4. Testes

`src/test/ai-operator-risk.test.ts` — 7 casos cobrindo:
- leituras classificadas como seguras
- operações internas (rascunho/memória) seguras
- escritas no ERP exigem aprovação
- envios para cliente (WhatsApp/cobrança/link) são CRITICAL
- ajuste de estoque é HIGH
- ações desconhecidas caem em HIGH (fail-closed)
- `propose_action` é seguro em si — risco vem da action proposta

Resultado do `npm test`: **9 arquivos, 33 testes, todos passam.**
Resultado do `npm run build`: **OK.**

## Política de segurança implementada

Classificação determinística em `supabase/functions/ai-operator-core/risk.ts`:

| Ação | Nível | Aprovação |
| --- | --- | --- |
| Leituras (search/list/get) | low | não |
| create_draft / add_draft_item / register_memory_note | low | não |
| create_service_order / schedule_service_order / apply_discount | high | sim |
| create_client / create_vessel / create_product | medium | sim |
| create_agenda_task / update_agenda_task | medium | sim |
| create_purchase_order | high | sim |
| send_whatsapp_message / send_collection_reminder / send_service_order_link | critical | sim |
| schedule_whatsapp_message | high | sim |
| adjust_inventory | high | sim |
| convert_draft_to_service_order | high | sim |
| **(qualquer ação desconhecida)** | **high** | **sim** |

## WhatsApp e canais

- Webhook existente (`whatsapp-webhook/index.ts`) **não foi modificado**.
- Bridge passiva via trigger SQL enfileira mensagens inbound em
  `ai_operator_channel_events` — sem disparar resposta automática.
- Mídias (`audio`/`image`/`document`/`video`) são enfileiradas com `media_url`,
  mas **transcrição/OCR multimodal não foi implementado neste ciclo** — exige
  credencial / serviço adicional. Está documentado como próximo passo.
- O assistente interno do ERP continua aceitando voz via SpeechRecognition do
  navegador (comportamento legado preservado).

## Cenário Raymarine (caso de aceitação)

No Modo Operador (beta), o usuário envia:

> *“Cliente quer orçamento para instalação de nova tela Raymarine no fly.
> Considere mão de obra, cabos, alimentação, NMEA 2000 e compatibilidade com
> equipamentos existentes.”*

O operador então:
1. Cria sessão (`ai_operator_sessions`).
2. Persiste a mensagem do usuário.
3. Chama tools SEGURAS — ex: `search_vessels`, `get_vessel_history` (quando
   embarcação for fornecida).
4. Chama `create_draft` (kind=`quote`) com `interpreted_intent`,
   `interpreted_category`, `pending_questions`, `next_steps`, `hypotheses`.
5. Chama `add_draft_item` para serviços/produtos/itens a cotar/deslocamento/
   engenharia/perguntas/riscos identificados.
6. Termina respondendo com resumo em markdown. **Nada é enviado ao cliente,
   nenhuma OS oficial é criada, nenhum técnico é agendado.**

Se o modelo tentar chamar diretamente uma tool sensível (`create_service_order`,
`send_whatsapp_message`), o gate determinístico BLOQUEIA no backend, registra
em `ai_operator_audit` com `event_type='tool_call_blocked'` e devolve ao
modelo a mensagem orientando o uso de `propose_action`. Aprovação humana
explícita (Approve no card) é obrigatória.

## Próximo macro ciclo recomendado

1. **Multimodalidade real:** transcrição de áudio + OCR de documentos
   recebidos via WhatsApp, alimentando o operador como input estruturado.
   Exige decisão sobre serviço (Gemini multimodal, OpenAI Whisper, etc.) e
   credencial.
2. **Execução real das pending actions aprovadas:** quando uma `pending_action`
   muda para `approved`, despachar para o edge function correspondente
   (whatsapp-send, criar OS, etc.) com idempotência e registro completo em
   `ai_operator_audit`.
3. **Conversão de rascunho → OS oficial:** action `convert_draft_to_service_order`
   já existe no gate; falta o executor.
4. **Painel dedicado de rascunhos** em rota própria (lista + filtros),
   além do card inline no widget.
5. **Processamento da fila `ai_operator_channel_events`** — worker dedicado
   que lê eventos `queued`, deduz cliente/lead, abre/recupera sessão e
   produz `response_suggestion` para a equipe.
6. **Adapter Evolution/n8n:** plugar o `ai-operator-channel-intake` como
   destino, mantendo Z-API ativo em paralelo até validação.

## Confirmações obrigatórias

- ✅ `main` não foi tocada.
- ✅ `staging/marineflow-functional` não foi merge nem alvo de push direto.
- ✅ `fix/service-order-signed-pdf` / `release/signature-security-hardening`
  não foram misturadas a esta entrega.
- ✅ Produção não foi tocada. Nenhum deploy executado.
- ✅ Nenhum force push, tag ou comando destrutivo.
- ✅ `.env` não foi lido. Nenhum segredo exposto. Migrations criadas no
  repositório e prontas para aplicação supervisionada em staging.
- ✅ Lovable não foi usado.
- ✅ HBR Operator / HBR Intelligence / Evolution / n8n não foram alterados.
- ✅ Webhook WhatsApp existente preservado integralmente.
- ✅ Schema existente preservado — todas as alterações são aditivas.
- ✅ Build OK; 33/33 testes passam.
