## Visão Geral

Implementar um **Agente de IA** integrado ao ERP, com chat flutuante disponível em todas as páginas autenticadas, capaz de **executar ações reais** no banco de dados (criar OS, agendar tarefas, cadastrar clientes, montar orçamentos, **enviar WhatsApp**) via *function calling* da Lovable AI Gateway (Gemini).

O agente conhece a página atual do usuário, confirma ações de gravação antes de executar e usa busca tolerante a erros de digitação.

---

## Como o usuário usará

- Botão flutuante (ícone Sparkles/Bot) no canto inferior direito, presente em todas as páginas internas.
- Clicar abre um painel lateral retrátil (Sheet) com o chat.
- Usuário escreve em linguagem natural ("crie uma OS para o barco do João amanhã às 10h", "envie um lembrete no WhatsApp para a Maria sobre a cobrança vencida", "cadastre o cliente Carlos, telefone 11 99999-0000").
- Respostas em **Markdown**, com indicador de "pensando…" enquanto a IA processa.
- Para ações de gravação/envio, a IA mostra um **resumo estruturado** e botões **Confirmar / Cancelar** antes de executar.
- Histórico da conversa mantido durante a sessão (memória local).

---

## Arquitetura

```text
┌─────────────────────────────┐
│  AIAgentWidget (frontend)   │
│  - Sheet flutuante           │
│  - Markdown + estados        │
│  - Envia: messages, route,   │
│    contexto da entidade      │
└──────────────┬──────────────┘
               │ supabase.functions.invoke('ai-agent')
               ▼
┌─────────────────────────────┐
│  Edge Function: ai-agent     │
│  - Lovable AI Gateway        │
│  - Modelo: gemini-2.5-pro    │
│  - Tools (function calling)  │
│  - Loop até resposta final   │
└──────┬───────────────┬──────┘
       │               │
       ▼               ▼
   Supabase       whatsapp-send-text
   (com JWT)      (edge function existente)
```

A edge function recebe `{ messages, context }` e roda um **loop de tool calls**: chama o gateway, se a resposta tiver `tool_calls`, executa-as no banco e devolve o resultado ao modelo, repetindo até obter resposta final em texto.

---

## Confirmação em duas etapas (para escritas/envios)

1. IA chama `propose_action({ action, payload, summary })` — tool **read-only** que apenas devolve o resumo ao chat.
2. Frontend renderiza um card com resumo + botões "Confirmar"/"Cancelar".
3. Ao confirmar, o frontend reenvia a conversa adicionando `"Confirmado pelo usuário"`, e a IA chama então a tool real (`create_service_order`, `send_whatsapp_message` etc.).

Tools de **leitura** executam direto, sem confirmação.

---

## Tools expostas ao modelo

**Leitura (executadas direto):**
- `search_clients(query)` — busca tolerante (ilike em nome/email/telefone/cnpj).
- `search_vessels(query, client_id?)`.
- `search_products(query)`.
- `list_agenda(date_from, date_to, technician_id?)`.
- `list_service_orders(status?, client_id?, vessel_id?, limit?)`.
- `get_service_order(id)` — detalhes + itens + serviços.
- `get_client_history(client_id)` — OSs anteriores.
- `list_pending_collections(client_id?)` — cobranças pendentes/atrasadas.

**Escrita (passam por `propose_action` antes):**
- `create_agenda_task({ title, scheduled_start_at, technician_user_id, client_id?, location?, notes? })`.
- `update_agenda_task({ id, ...campos })`.
- `create_service_order({ client_id, vessel_id, problem_description?, scheduled_start_at?, items?, services? })`.
- `update_service_order_status({ id, status })`.
- `add_service_order_item({ service_order_id, product_id, quantity })`.
- `apply_service_order_discount({ id, discount_amount })`.
- `create_client({ full_name_or_company_name, type, phone?, email?, cpf_cnpj? })`.
- `create_vessel({ client_id, boat_name, manufacturer?, model?, year?, marina_id? })`.
- `create_product({ product_name, sku?, sale_price?, cost_price?, unit? })`.

**WhatsApp (passam por `propose_action` antes):**
- `send_whatsapp_message({ to_phone | client_id, message })` — envia texto livre via Z-API (chama a edge function existente `whatsapp-send-text`).
- `send_collection_reminder({ collection_id, custom_message? })` — busca dados da cobrança, monta mensagem padrão (template de cobrança) e envia via Z-API; registra no `whatsapp_send_log` se aplicável.
- `send_service_order_link({ service_order_id, client_id, custom_message? })` — envia o link público da OS (`/view/:share_token`) para o cliente assinar/visualizar.

A diferença "orçamento vs OS" é tratada via `status='draft'` + `quote_validity_date`.

---

## System prompt (resumo)

> Você é o assistente do MarineFlow ERP. Use as ferramentas para consultar e modificar dados. **Antes de qualquer ação de gravação ou envio de WhatsApp, sempre chame `propose_action` primeiro** com um resumo claro em markdown e aguarde confirmação. O usuário está atualmente na rota `{route}` com contexto `{contextId}` — use isso para inferir clientes/embarcações/OS quando ele disser "este", "ele", "essa OS". Para buscas, use `search_*` e seja tolerante a erros de digitação. Mensagens de WhatsApp devem ser cordiais, em português, sem emojis excessivos, e sempre identificar o remetente (empresa). Responda em português, formate com markdown.

---

## Arquivos a criar/editar

**Novos:**
- `supabase/functions/ai-agent/index.ts` — edge function: loop de tool calling, definição de todas as tools, validação Zod, RLS via JWT do usuário, integração com `whatsapp-send-text`.
- `src/components/ai/AIAgentWidget.tsx` — botão flutuante + Sheet com chat.
- `src/components/ai/AIChatMessage.tsx` — renderização com `react-markdown`.
- `src/components/ai/AIConfirmCard.tsx` — card de confirmação para `propose_action`.
- `src/hooks/use-ai-agent.ts` — gerencia mensagens, envio, contexto da rota.
- `src/lib/ai-context.ts` — extrai `{ route, entityId, entityType }` de `useLocation`/`useParams`.

**Editados:**
- `src/components/AppLayout.tsx` — montar `<AIAgentWidget />` ao lado do `<PWAInstallPrompt />` (apenas para usuários autenticados).
- `package.json` — adicionar `react-markdown` + `remark-gfm`.

---

## Detalhes técnicos da edge function

- Recebe `Authorization: Bearer <jwt>`; cria cliente Supabase com esse JWT → **todas as escritas respeitam RLS** (auth.uid() do usuário, usado em `created_by`).
- Usa `LOVABLE_API_KEY` (já configurada) para chamar `https://ai.gateway.lovable.dev/v1/chat/completions`.
- Modelo padrão: `google/gemini-2.5-pro` (melhor reasoning + tool calling).
- Cada tool com `parameters` JSON Schema; valida com Zod antes de executar.
- Limite: **máx. 8 iterações** de tool-calling por requisição.
- Trata 429 (rate limit) e 402 (créditos) com mensagens amigáveis.
- Para `send_whatsapp_message` e similares: invoca a edge function `whatsapp-send-text` existente passando o JWT do usuário, garantindo que tokens Z-API permaneçam só no backend.
- CORS liberado.

---

## Comportamento UX

- Widget só aparece quando `user` está logado (via `useAuth`).
- Estado "pensando" mostra spinner + texto "Processando…" / "Executando ação…" quando há tool em execução.
- Após `propose_action`, chat exibe `AIConfirmCard`:
  - Título da ação (ex.: "Enviar WhatsApp para Maria Silva")
  - Resumo em markdown (destinatário, prévia da mensagem, valor, etc.)
  - Botões **Confirmar** / **Cancelar**
- Ao concluir ação de escrita, invalida queries do React Query relacionadas (clientes, OSs, agenda, cobranças) para refletir mudanças imediatamente.
- Botão "Nova conversa" limpa histórico.

---

## Segurança

- Edge function valida JWT antes de executar.
- Operações no banco usam cliente Supabase com JWT do usuário → RLS aplicada.
- Tools de escrita validam payload com Zod antes de tocar o banco.
- Nenhum SQL bruto; apenas `supabase-js` tipado.
- Tokens Z-API permanecem no backend (chamada via edge function existente).
- Envio de WhatsApp **sempre** exige confirmação humana via `propose_action`.

---

## Fora do escopo (iterações futuras)

- Persistência de histórico de conversas no banco.
- Streaming token-a-token (a v1 usa resposta não-stream para simplificar tool-calling).
- Voz (speech-to-text).
- Envio em lote de WhatsApp (ex.: "lembrar todos os clientes com cobrança vencida") — adicionável depois com salvaguardas extras.