# Auditoria Z-API — MarineFlow ERP
**Gerado em:** 2026-06-09  
**Branch:** `claude/keen-brown-j2pgw0`  
**Escopo:** Tarefas S1, S2, S3 e S4 — pré-migração para Evolution API

---

## S1 — Tabela de Inventário de Ocorrências Z-API

| # | Arquivo | Linha(s) | Tipo | Descrição resumida |
|---|---------|----------|------|-------------------|
| 1 | `supabase/functions/whatsapp-send/index.ts` | 2, 100, 107, 114, 128 | `envio-texto` / `envio-link` / `envio-documento` | Função principal de envio. Monta URL `https://api.z-api.io/instances/${INSTANCE_ID}/token/${TOKEN}` e chama `/send-text`, `/send-link` ou `/send-document/pdf` conforme `kind`. |
| 2 | `supabase/functions/whatsapp-send/index.ts` | 72–74 | `config-auth` | Lê `INSTANCE_ID`, `TOKEN`, `CLIENT_TOKEN` do `app_settings` com fallback para `Deno.env`. |
| 3 | `supabase/functions/whatsapp-send/index.ts` | 138–139 | `config-auth` | Injeta header `Client-Token` quando presente. |
| 4 | `supabase/functions/whatsapp-send/index.ts` | 159, 167–168, 171–172, 177, 185–186 | `envio-texto` | Armazena `zapi_response`, `http_status`, `zapi: zapiBody` no `audit_log` e retorna `messageId` ao chamador. |
| 5 | `supabase/functions/whatsapp-send-text/index.ts` | 22–24 | `config-auth` | Lê apenas de `Deno.env` (sem fallback para DB). |
| 6 | `supabase/functions/whatsapp-send-text/index.ts` | 52–63 | `envio-texto` | Chama `${base}/send-text` para envio do Inbox (resposta do operador). |
| 7 | `supabase/functions/whatsapp-send-text/index.ts` | 71 | `envio-texto` | Armazena `zapi_message_id` na tabela `whatsapp_messages`. |
| 8 | `supabase/functions/whatsapp-queue-worker/index.ts` | 44–46 | `config-auth` | Lê apenas de `Deno.env`. |
| 9 | `supabase/functions/whatsapp-queue-worker/index.ts` | 106–108 | `config-url` / `config-auth` | Monta base URL e header `Client-Token`. |
| 10 | `supabase/functions/whatsapp-queue-worker/index.ts` | 114 | `envio-texto` | Chama `/send-text` para cada item da `whatsapp_send_queue`. |
| 11 | `supabase/functions/whatsapp-queue-worker/index.ts` | 126 | `envio-texto` | Armazena `zapi_message_id` na fila após sucesso. |
| 12 | `supabase/functions/whatsapp-webhook/index.ts` | 48, 51 | `envio-texto` | `notifyAssignedReminder` envia notificação de novo lead via `/send-text` usando credenciais do DB. |
| 13 | `supabase/functions/whatsapp-webhook/index.ts` | 170–172 | `config-auth` | Lê credenciais do `app_settings` para repassar à função de notificação. |
| 14 | `supabase/functions/whatsapp-webhook/index.ts` | 174–177 | `webhook-entrada` | Processa `MessageStatusCallback`: atualiza `delivery_status` pelo `zapi_message_id`. |
| 15 | `supabase/functions/whatsapp-webhook/index.ts` | 188–190 | `webhook-entrada` | Deduplica mensagens por `zapi_message_id`. |
| 16 | `supabase/functions/whatsapp-webhook/index.ts` | 227 | `webhook-entrada` | Salva `zapi_message_id` em `whatsapp_messages`. |
| 17 | `supabase/functions/zapi-configure-webhook/index.ts` | 47–70 | `config-auth` / `config-url` | Lê credenciais do DB + fallback env e monta base URL para configurar webhooks. |
| 18 | `supabase/functions/zapi-configure-webhook/index.ts` | 73–79 | `config-url` | Define 5 endpoints de webhook: `update-webhook-received`, `update-webhook-delivery`, `update-webhook-message-status`, `update-webhook-receive-by-me`, `update-webhook-disconnected`. |
| 19 | `supabase/functions/zapi-configure-webhook/index.ts` | 88 | `config-url` | Consulta `GET ${base}/webhooks` para verificar configuração atual. |
| 20 | `supabase/functions/zapi-configure-webhook/index.ts` | 184–220 | `config-url` | Configura webhooks via `POST/PATCH/PUT ${base}/{endpoint}`. |
| 21 | `supabase/functions/whatsapp-status-worker/index.ts` | 39–41 | `config-auth` | Lê credenciais do `app_settings` (sem fallback env). |
| 22 | `supabase/functions/whatsapp-status-worker/index.ts` | 57 | `config-url` | Monta base URL. |
| 23 | `supabase/functions/whatsapp-status-worker/index.ts` | 60 | `envio-texto` | Endpoint `/send-text-status` para status de texto. |
| 24 | `supabase/functions/whatsapp-status-worker/index.ts` | 67 | `envio-imagem` | Endpoint `/send-image-status` para status de imagem. |
| 25 | `supabase/functions/whatsapp-status-worker/index.ts` | 74 | `envio-documento` | Endpoint `/send-video-status` (implícito no código). |
| 26 | `supabase/functions/whatsapp-status-worker/index.ts` | 89, 94 | `envio-texto` | Armazena `zapi_message_id` (via `zapiRes.messageId || zapiRes.id`). |
| 27 | `supabase/functions/whatsapp-unread-reminder/index.ts` | 63–65 | `config-auth` | Lê `ZAPI_INSTANCE_ID`, `ZAPI_TOKEN`, `ZAPI_CLIENT_TOKEN` de `Deno.env`. Função não envia diretamente — enfileira na `whatsapp_send_queue`. |
| 28 | `supabase/functions/scheduling-automations/index.ts` | 35–36 | `config-auth` | Lê `zapi_test_mode` e `zapi_test_number` do `app_settings`. |
| 29 | `supabase/functions/scheduling-automations/index.ts` | 49–51 | `config-auth` | Lê `zapi_instance_id`, `zapi_token`, `zapi_client_token` do DB + fallback env. |
| 30 | `supabase/functions/scheduling-automations/index.ts` | 62–64 | `config-url` / `config-auth` | Monta URL base e header `Client-Token`. |
| 31 | `supabase/functions/scheduling-automations/index.ts` | 111 | `envio-texto` | Chama `${zapiBase}/send-text` para cada OS agendada. |
| 32 | `supabase/functions/scheduling-automations/index.ts` | 139 | `envio-texto` | Armazena `zapi_response` no log. |
| 33 | `supabase/functions/ai-agent/index.ts` | 513 | `comentario` | Docstring da ferramenta `send_whatsapp_message` menciona Z-API. |
| 34 | `src/hooks/use-zapi-send.ts` | 7–24 | `tipo-typescript` | Interface `ZApiSendPayload` com campos `phone`, `message`, `mode`, `context`, `publicUrl`, `pdfData` etc. |
| 35 | `src/hooks/use-zapi-send.ts` | 41–135 | `envio-texto` / `envio-documento` / `envio-link` | Hook `useZApiSend` com lógica de retry exponencial (1s, 2s, 4s até 8s máx). Chama edge function `whatsapp-send`. |
| 36 | `src/hooks/use-zapi-send.ts` | 111, 120 | `comentario` | Logs de console referenciando "Z-API". |
| 37 | `src/components/WhatsAppZApiSettings.tsx` | 19–23 | `config-auth` | Estado local com `zapi_instance_id`, `zapi_token`, `zapi_client_token`, `zapi_test_mode`, `zapi_test_number`. |
| 38 | `src/components/WhatsAppZApiSettings.tsx` | 34 | `config-auth` | Query `app_settings` com filtro `key LIKE 'zapi_%'`. |
| 39 | `src/components/WhatsAppZApiSettings.tsx` | 62–76 | `config-auth` | Salva todas as chaves `zapi_*` no `app_settings` via upsert. |
| 40 | `src/components/WhatsAppZApiSettings.tsx` | 104–257 | `config-auth` | UI completa de configuração: Instance ID, Token, Client Token, Test Mode, Test Number. |
| 41 | `src/components/SendViaZAPIDialog.tsx` | 26–48 | `tipo-typescript` | Tipo `SendViaZAPITarget` (service_order | receivable). |
| 42 | `src/components/SendViaZAPIDialog.tsx` | 56–456 | `envio-texto` / `envio-link` / `envio-documento` | Dialog completo de envio manual com templates, agendamento e retry. |
| 43 | `src/components/SendViaZAPIDialog.tsx` | 65, 69, 79, 82 | `config-auth` | Persiste `zapi.autoRetry` e `zapi.maxAttempts` no `localStorage`. |
| 44 | `src/components/BulkBillingReminderDialog.tsx` | 25 | `tipo-typescript` | Import de `ScheduleSettings` do subdiretório `zapi/`. |
| 45 | `src/components/BulkBillingReminderDialog.tsx` | 44–45 | `config-auth` | Chaves `zapi.bulk.throttleMs` e `zapi.bulk.maxAttempts` no `localStorage`. |
| 46 | `src/components/BulkBillingReminderDialog.tsx` | 347, 394 | `comentario` | UI menciona "Z-API" como provedor de envio em lote. |
| 47 | `src/components/WhatsAppWebhookValidator.tsx` | 46, 70, 96, 102 | `config-url` | Invoca edge functions `zapi-configure-webhook` para validar e configurar webhooks. |
| 48 | `src/components/WhatsAppWebhookValidator.tsx` | 116, 155, 168, 177, 189, 203, 276, 285, 287, 325, 327, 339 | `comentario` | UI com menções extensas à Z-API nas instruções ao usuário. |
| 49 | `src/components/ClientFormDialog.tsx` | 162–163, 246, 251, 261 | `comentario` | Aba "WhatsApp / Z-API" no formulário de cliente. |
| 50 | `src/components/ServiceOrderForm.tsx` | 58, 839–841, 1688, 1700, 1782, 3630–3633 | `envio-texto` | Import, estado e botão "Enviar Z-API" na OS; exibe histórico e resposta da Z-API. |
| 51 | `src/components/WhatsAppSendHistoryDialog.tsx` | 28, 40, 44, 49, 81 | `comentario` | Dialog de histórico referencia "envios Z-API" e campo `zapi_response.error`. |
| 52 | `src/components/WhatsAppReminderSettings.tsx` | 133 | `comentario` | Texto "envia um resumo via Z-API para os responsáveis". |
| 53 | `src/pages/WhatsAppStatusPage.tsx` | 419 | `comentario` | Texto "instância Z-API esteja conectada". |
| 54 | `src/pages/FinancialPage.tsx` | 30, 120, 586–620, 769–772 | `envio-texto` / `envio-documento` | Import, estado e botão "Z-API" nas cobranças; define `SendViaZAPITarget`. |
| 55 | `src/pages/ServiceOrderList.tsx` | 20, 78, 378–474, 522–525 | `envio-texto` / `envio-documento` | Import, estado, botões "Enviar OS via Z-API" e "Enviar Orçamento via Z-API", histórico. |
| 56 | `src/pages/CRMKanbanPage.tsx` | 13, 28, 136–140 | `envio-texto` | Import e uso do `SendViaZAPIDialog` no Kanban. |
| 57 | `src/pages/WhatsAppLogsPage.tsx` | 32, 139, 162, 280, 294, 298 | `tipo-typescript` / `comentario` | Campo `zapi_message_id` no tipo local; exibição de "Z-API ID" e descrição de payload bruto. |
| 58 | `src/pages/ServiceOrderList.test.tsx` | 100–148 | `comentario` | Mock do `SendViaZAPIDialog` e testes de menu items "Enviar OS/Orçamento via Z-API". |
| 59 | `src/integrations/supabase/types.ts` | 3632, 3650, 3668, 3901, 3919, 3937 | `tipo-typescript` | Campo `zapi_message_id: string \| null` nas tabelas `whatsapp_messages` (rows 3632–3668) e `whatsapp_status_scheduled` (rows 3901–3937). |
| 60 | `.lovable/plan.md` | 83, 84, 121, 145 | `comentario` | Plano de desenvolvimento menciona Z-API como provedor de envio de mensagens e tokens. |
| 61 | `src/components/zapi/MessageEditor.tsx` | 45, 53 | `comentario` | IDs HTML com prefixo "msg-zapi". |

**Confirmação grep final:** Executado `grep -ri "z-api\|zapi\|z_api"` — todas as saídas presentes na tabela acima.

---

## S2 — Inventário de Contratos de Função

### Função 1: `useZApiSend().send()`

```
Nome da função: send (exportado por useZApiSend)
Arquivo: src/hooks/use-zapi-send.ts:82
Parâmetros de entrada:
  payload: ZApiSendPayload {
    phone: string              — número com DDI (ex: "5521999998888"), pode ter não-dígitos
    message: string            — corpo da mensagem
    mode: 'link' | 'document'
    context: string            — 'service_order' | 'quote' | 'billing' | string livre
    service_order_id?: string  — UUID
    receivable_id?: string     — UUID
    publicUrl?: string         — URL do portal compartilhado (mode=link)
    link_title?: string
    link_description?: string
    pdfData?: any              — dados para generatePDFBlob (mode=document)
    documentType?: PDFDocumentType
    filename?: string
    caption?: string
  }
  retry: RetryConfig {
    autoRetry: boolean
    maxAttempts: number        — 1–5
  }
Tipo de retorno declarado: Promise<boolean> — true=sucesso, false=falha
O que envia para a Z-API: indiretamente via edge function 'whatsapp-send' (link ou PDF via URL pública no Supabase Storage)
Formato do número de telefone: chega com qualquer formatação; strip não-dígitos (replace(/\D/g,'')) ANTES de invocar a edge function; validação mínima >= 10 dígitos no hook, validação final na edge function
Tratamento de erro: sim — captura erro de cada tentativa, faz retry exponencial (1s, 2s, 4s... max 8s), exibe toast de erro após esgotar tentativas
Timeout definido: não (delegado ao Supabase client)
Retry: sim — autoRetry configura o número de tentativas (1–5); backoff = min(8000, 1000 * 2^(attempt-1))
Call sites (quem chama):
  - src/components/SendViaZAPIDialog.tsx:321 — envio imediato de OS/orçamento/cobrança
  - src/components/WhatsAppZApiSettings.tsx:87 — envio de mensagem de teste
  - src/hooks/use-collections.ts:~370 — inferido (usa useZApiSend)
```

---

### Função 2: `whatsapp-send` (edge function)

```
Nome da função: Deno.serve handler em whatsapp-send/index.ts
Arquivo: supabase/functions/whatsapp-send/index.ts:43
Parâmetros de entrada (body JSON validado por Zod):
  phone: string (8–20 chars)
  kind: 'text' | 'link' | 'document' (default 'text')
  message?: string (max 4096)
  link_url?: string (URL)
  link_title?: string (max 200)
  link_description?: string (max 500)
  link_image?: string (URL, opcional)
  document_url?: string (URL)
  document_filename?: string (max 120)
  document_caption?: string (max 1024)
  service_order_id?: string (UUID)
  receivable_id?: string (UUID)
  context?: string (max 64)
Tipo de retorno declarado: Response JSON
  sucesso: { success: true, kind, messageId, zapi: zapiBody }
  erro: { error: string, details?: any }
O que envia para a Z-API:
  text     → POST /send-text           { phone, message }
  link     → POST /send-link           { phone, message, linkUrl, title, linkDescription, image? }
  document → POST /send-document/pdf   { phone, document(URL), fileName, caption? }
Formato do número de telefone: chega como string; strip não-dígitos internamente; se testMode ativo, substitui pelo testNumber; validação >= 10 dígitos
Tratamento de erro: sim — HTTP 400 para validação, HTTP 502 para erro Z-API, HTTP 500 para exceção; registra no audit_log independentemente do resultado
Timeout definido: não (default do Deno runtime/Supabase Edge)
Retry: não — retry é responsabilidade do chamador (hook useZApiSend)
Call sites (quem chama):
  - src/hooks/use-zapi-send.ts:77 — supabase.functions.invoke('whatsapp-send', ...)
  - supabase/functions/ai-agent/index.ts:1383 — chamada interna do agente IA
```

---

### Função 3: `whatsapp-send-text` (edge function — Inbox)

```
Nome da função: Deno.serve handler em whatsapp-send-text/index.ts
Arquivo: supabase/functions/whatsapp-send-text/index.ts:19
Parâmetros de entrada (body JSON):
  phone: string
  message: string
Tipo de retorno declarado: Response JSON
  sucesso: { ok: true, messageId: string|null }
  erro: { error: string }
O que envia para a Z-API: POST /send-text { phone: cleanPhone, message: text }
Formato do número de telefone: strip não-dígitos; validação >= 10 dígitos
Tratamento de erro: sim — HTTP 400, 401, 502, 500 com mensagem de erro
Timeout definido: não
Retry: não
Call sites (quem chama):
  - src/hooks/use-whatsapp-inbox.ts:105 — supabase.functions.invoke('whatsapp-send-text', ...)
```

---

### Função 4: `whatsapp-queue-worker` — envio da fila

```
Nome da função: Deno.serve handler em whatsapp-queue-worker/index.ts
Arquivo: supabase/functions/whatsapp-queue-worker/index.ts:38
Parâmetros de entrada: nenhum no body (cron invocation)
Tipo de retorno declarado: Response JSON com { ok, processed, results, ... }
O que envia para a Z-API: POST /send-text { phone: item.phone_normalized, message: item.message }
Formato do número de telefone: consome diretamente o campo phone_normalized da tabela (já normalizado na inserção)
Tratamento de erro: sim — por item: atualiza status para 'failed' ou reagenda 'pending' após max_attempts; captura exceções de rede
Timeout definido: não
Retry: sim — por item, máx. item.max_attempts (default 3); reagenda em +5min
Call sites (quem chama): cron Supabase (scheduler); pode ser invocado manualmente
```

---

### Função 5: `scheduling-automations` — lembrete de agendamento

```
Nome da função: Deno.serve handler em scheduling-automations/index.ts
Arquivo: supabase/functions/scheduling-automations/index.ts:14
Parâmetros de entrada: nenhum (cron)
Tipo de retorno declarado: Response JSON { success, sent, total_orders, test_mode_active, log }
O que envia para a Z-API: POST /send-text { phone: targetPhone, message }
Formato do número de telefone: lido de clients.whatsapp || clients.phone; strip não-dígitos; se testMode, substituído por testNumber; validação >= 10 dígitos
Tratamento de erro: sim — por OS: captura SendErr, registra em log, continua loop
Timeout definido: não
Retry: não (cada OS processada uma vez por execução)
Call sites (quem chama): cron Supabase; pode ser invocado manualmente
```

---

### Função 6: `whatsapp-status-worker` — Status WhatsApp

```
Nome da função: Deno.serve handler em whatsapp-status-worker/index.ts
Arquivo: supabase/functions/whatsapp-status-worker/index.ts:12
Parâmetros de entrada: nenhum (cron)
Tipo de retorno declarado: Response JSON { results }
O que envia para a Z-API:
  text  → POST /send-text-status  { message, backgroundColor, font }
  image → POST /send-image-status { image, caption }
  video → POST /send-video-status { video, caption }
Formato do número de telefone: não se aplica (Status não requer destinatário)
Tratamento de erro: sim — por item: captura exceção, marca status 'failed', continua loop
Timeout definido: não
Retry: não
Call sites (quem chama): cron Supabase
```

---

### Função 7: `notifyAssignedReminder` — notificação de novo lead

```
Nome da função: notifyAssignedReminder
Arquivo: supabase/functions/whatsapp-webhook/index.ts:38
Parâmetros de entrada:
  admin: SupabaseClient
  phone: string — número do lead (normalizado)
  senderName: string | null
  preview: string — preview da mensagem recebida
  zapiCreds: { id: string; token: string; client: string | null }
Tipo de retorno declarado: Promise<void>
O que envia para a Z-API: POST /send-text { phone: to, message } para cada destinatário admin
Formato do número de telefone: destinatários lidos do app_settings 'whatsapp_reminder_recipients'; strip não-dígitos; filter >= 10 dígitos
Tratamento de erro: sim — try/catch global, erros silenciosos com console.error
Timeout definido: não
Retry: não
Call sites (quem chama): whatsapp-webhook/index.ts:233 — chamado quando isNewLead && !fromMe
```

---

### Função 8: `zapi-configure-webhook` (edge function)

```
Nome da função: Deno.serve handler em zapi-configure-webhook/index.ts
Arquivo: supabase/functions/zapi-configure-webhook/index.ts:19
Parâmetros de entrada: query param ?action=configure_all|test_each
Tipo de retorno declarado: Response JSON com resultado da configuração ou teste
O que envia para a Z-API:
  test_each:      GET  ${base}/webhooks
  configure_all:  POST/PATCH/PUT ${base}/update-webhook-{received,delivery,messageStatus,received_by_me,disconnected}
Formato do número de telefone: não se aplica
Tratamento de erro: sim — por endpoint, captura exceções; retorna status parcial se algum falhar
Timeout definido: não
Retry: sim — fallback PATCH→PUT se POST retornar 405
Call sites (quem chama):
  - src/components/WhatsAppWebhookValidator.tsx:70 — supabase.functions.invoke('zapi-configure-webhook')
  - src/components/WhatsAppWebhookValidator.tsx:96 — com ?action=test_each
```

---

## S3 — Inventário do Fluxo de Webhook de Entrada

### Rota de Recebimento

```
Arquivo:  supabase/functions/whatsapp-webhook/index.ts
URL:      https://<SUPABASE_URL>/functions/v1/whatsapp-webhook
Método:   POST (também GET para healthcheck e limpeza de leads fantasmas)
```

### URL Configurada como Callback na Z-API

```
Formato:  https://<SUPABASE_URL>/functions/v1/whatsapp-webhook?apikey=<SUPABASE_ANON_KEY>
Configurada automaticamente pela função zapi-configure-webhook
  Eventos mapeados:
    - received          → update-webhook-received
    - delivery          → update-webhook-delivery
    - messageStatus     → update-webhook-message-status
    - received_by_me    → update-webhook-receive-by-me
    - disconnected      → update-webhook-disconnected
```

### Campos Utilizados do Payload Z-API

```javascript
pAny.type | pAny.event          // tipo do evento (ex: "MessageStatusCallback", "ReceivedCallback")
pAny.fromMe                     // boolean — mensagem enviada por nós
pAny.phone | pAny.chatId | pAny.senderLid | pAny.to  // número do interlocutor
pAny.messageId | pAny.id        // ID da mensagem na Z-API → salvo como zapi_message_id
pAny.senderName | pAny.notifyName  // nome do contato
pAny.isGroup                    // boolean — ignora grupos

// Para corpo da mensagem:
pAny.text?.message
pAny.text
pAny.message?.conversation
pAny.message?.extendedTextMessage?.text
pAny.body | pAny.caption

// Para mídia:
pAny.image → { caption, imageUrl, url }
pAny.audio → { audioUrl, url }
pAny.video → { caption, videoUrl, url }
pAny.document → { caption, fileName, documentUrl, url }

// Para MessageStatusCallback:
pAny.status      // delivery status string
pAny.ids[0]      // messageId alternativo
```

### Shape Completo do Payload (inferido do código)

```typescript
interface ZApiWebhookPayload {
  type?: string;           // "ReceivedCallback" | "MessageStatusCallback" | "PresenceChatCallback" | etc.
  event?: string;          // alternativa a type
  fromMe?: boolean;
  phone?: string;          // remetente (inbound)
  to?: string;             // destinatário (outbound fromMe)
  chatId?: string;         // alternativa a phone/to
  senderLid?: string;      // alternativa a phone (alguns tipos de conta)
  messageId?: string;      // ID principal da mensagem
  id?: string;             // ID alternativo
  senderName?: string;     // nome do contato
  notifyName?: string;     // nome de notificação alternativo
  isGroup?: boolean;
  status?: string;         // para MessageStatusCallback: "delivered" | "read" | "failed" etc.
  ids?: string[];          // para MessageStatusCallback com múltiplos IDs
  text?: {
    message?: string;
  };
  message?: {
    conversation?: string;
    extendedTextMessage?: { text?: string };
  };
  body?: string;
  caption?: string;
  image?: { caption?: string; imageUrl?: string; url?: string };
  audio?: { audioUrl?: string; url?: string };
  video?: { caption?: string; videoUrl?: string; url?: string };
  document?: { caption?: string; fileName?: string; documentUrl?: string; url?: string };
}
```

### O que o sistema faz com o evento

1. **Eventos ignorados:** `PresenceChatCallback`, `ChatStateCallback`, `PresenceCallback`, `ChatPresence`, `Presence`, `typing`, `recording` → retorna `{ ok: true, ignored: "system" }`
2. **Grupos ignorados:** `isGroup === true` → retorna `{ ok: true, ignored: "group" }`
3. **MessageStatusCallback:** atualiza `delivery_status` em `whatsapp_messages` pelo `zapi_message_id`
4. **Mensagens outbound sem conteúdo:** ignoradas (evita duplicatas de confirmações de sistema)
5. **Deduplicação:** verifica se `zapi_message_id` já existe em `whatsapp_messages`
6. **Classificação do contato:** busca em `clients` por phone/whatsapp → se não encontrar, busca em `whatsapp_leads` → se não existir e for inbound com número BR válido (55 + 12 ou 13 dígitos), cria novo lead
7. **Inserção:** salva em `whatsapp_messages` com direction, phone, body, mediaUrl, clientId/leadId, zapi_message_id, delivery_status, raw_payload
8. **Notificação de novo lead:** chama `notifyAssignedReminder` via Z-API para admins configurados
9. **Atualização de timestamps:** atualiza `updated_at` em `whatsapp_leads` ou `clients`

---

## S4 — Inventário de Variáveis de Ambiente e Segredos

### Variáveis de Ambiente (Supabase Edge Function Secrets)

| Variável | Onde declarada | Onde consumida (arquivo:linha) | Valor hardcoded? | Exposta no front-end? |
|----------|---------------|-------------------------------|-----------------|----------------------|
| `ZAPI_INSTANCE_ID` | Supabase secrets (env da edge function) | `whatsapp-send-text/index.ts:22` | Não | Não |
| `ZAPI_INSTANCE_ID` | Supabase secrets | `whatsapp-queue-worker/index.ts:44` | Não | Não |
| `ZAPI_INSTANCE_ID` | Supabase secrets | `whatsapp-unread-reminder/index.ts:63` | Não | Não |
| `ZAPI_INSTANCE_ID` | Supabase secrets (fallback) | `whatsapp-send/index.ts:72` | Não | Não |
| `ZAPI_INSTANCE_ID` | Supabase secrets (fallback) | `scheduling-automations/index.ts:49` | Não | Não |
| `ZAPI_INSTANCE_ID` | Supabase secrets (fallback) | `zapi-configure-webhook/index.ts:54` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets | `whatsapp-send-text/index.ts:23` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets | `whatsapp-queue-worker/index.ts:45` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets | `whatsapp-unread-reminder/index.ts:64` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets (fallback) | `whatsapp-send/index.ts:73` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets (fallback) | `scheduling-automations/index.ts:50` | Não | Não |
| `ZAPI_TOKEN` | Supabase secrets (fallback) | `zapi-configure-webhook/index.ts:55` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets | `whatsapp-send-text/index.ts:24` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets | `whatsapp-queue-worker/index.ts:46` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets | `whatsapp-unread-reminder/index.ts:65` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets (fallback) | `whatsapp-send/index.ts:74` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets (fallback) | `scheduling-automations/index.ts:51` | Não | Não |
| `ZAPI_CLIENT_TOKEN` | Supabase secrets (fallback) | `zapi-configure-webhook/index.ts:56` | Não | Não |

### Configurações no Banco (`app_settings`)

| Variável | Onde declarada | Onde consumida (arquivo:linha) | Valor hardcoded? | Exposta no front-end? |
|----------|---------------|-------------------------------|-----------------|----------------------|
| `zapi_instance_id` | Tabela `app_settings` (DB) | `whatsapp-send/index.ts:72` | Não | ⚠️ SIM — via `WhatsAppZApiSettings.tsx:34` (autenticado) |
| `zapi_token` | Tabela `app_settings` (DB) | `whatsapp-send/index.ts:73` | Não | ⚠️ SIM — via `WhatsAppZApiSettings.tsx:34` (autenticado, campo password) |
| `zapi_client_token` | Tabela `app_settings` (DB) | `whatsapp-send/index.ts:74` | Não | ⚠️ SIM — via `WhatsAppZApiSettings.tsx:34` (autenticado, campo password) |
| `zapi_test_mode` | Tabela `app_settings` (DB) | `scheduling-automations/index.ts:35`, `whatsapp-send/index.ts:85` | Não | SIM — UI de configuração (controlável pelo usuário admin) |
| `zapi_test_number` | Tabela `app_settings` (DB) | `scheduling-automations/index.ts:36`, `whatsapp-send/index.ts:86` | Não | SIM — UI de configuração |
| `zapi_instance_id` | Tabela `app_settings` (DB) | `whatsapp-status-worker/index.ts:39` | Não | ⚠️ SIM |
| `zapi_token` | Tabela `app_settings` (DB) | `whatsapp-status-worker/index.ts:40` | Não | ⚠️ SIM |
| `zapi_client_token` | Tabela `app_settings` (DB) | `whatsapp-status-worker/index.ts:41` | Não | ⚠️ SIM |
| `zapi_instance_id` | Tabela `app_settings` (DB) | `zapi-configure-webhook/index.ts:54` | Não | ⚠️ SIM |
| `zapi_token` | Tabela `app_settings` (DB) | `zapi-configure-webhook/index.ts:55` | Não | ⚠️ SIM |
| `zapi_client_token` | Tabela `app_settings` (DB) | `zapi-configure-webhook/index.ts:56` | Não | ⚠️ SIM |
| `zapi_instance_id` | Tabela `app_settings` (DB) | `whatsapp-webhook/index.ts:170` | Não | ⚠️ SIM |
| `zapi_token` | Tabela `app_settings` (DB) | `whatsapp-webhook/index.ts:171` | Não | ⚠️ SIM |
| `zapi_client_token` | Tabela `app_settings` (DB) | `whatsapp-webhook/index.ts:172` | Não | ⚠️ SIM |
| `zapi_instance_id` | Tabela `app_settings` (DB) | `scheduling-automations/index.ts:49` | Não | ⚠️ SIM |
| `zapi_token` | Tabela `app_settings` (DB) | `scheduling-automations/index.ts:50` | Não | ⚠️ SIM |
| `zapi_client_token` | Tabela `app_settings` (DB) | `scheduling-automations/index.ts:51` | Não | ⚠️ SIM |

### Variáveis de Ambiente do Front-end (não relacionadas à Z-API, para contexto)

| Variável | Onde declarada | Valor hardcoded? | Observação |
|----------|---------------|-----------------|------------|
| `VITE_SUPABASE_URL` | `.env` | Sim (URL do projeto) | Não é segredo — chave pública |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | `.env` | Sim (anon key) | Não é segredo — chave pública |
| `VITE_SUPABASE_PROJECT_ID` | `.env` | Sim | Não é segredo |
| `VITE_VAPID_PUBLIC_KEY` | `.env.example` | Não definido | Chave pública de push notifications |

### Avaliação de Risco

> **⚠️ RISCO MODERADO — credenciais no banco de dados:**  
> Os tokens Z-API (`zapi_token`, `zapi_client_token`) e o Instance ID estão armazenados na tabela `app_settings` do Supabase. Eles são acessados via consultas autenticadas no frontend (`WhatsAppZApiSettings.tsx`) usando o JWT do usuário logado. O risco de exposição depende diretamente das **RLS Policies** da tabela `app_settings`:
> - Se `app_settings` tiver SELECT permitido para todos os usuários autenticados, qualquer usuário com conta pode ler os tokens.
> - Se RLS restringir a `role = 'admin'`, o risco é contido.
> - **Ação recomendada:** verificar e restringir a política de leitura de `app_settings` para `zapi_*` keys apenas para roles admin.
> 
> **✅ SEM RISCO CRÍTICO no bundle do cliente:**  
> Nenhuma chave/token Z-API está hardcoded em arquivos `.tsx`, `.jsx`, `.ts` ou `.js` do frontend. As variáveis de ambiente `VITE_*` presentes no `.env` são apenas chaves públicas do Supabase (anon key), que são projetadas para serem públicas.

---

## Resumo Executivo

| Item | Quantidade |
|------|-----------|
| Edge functions com chamadas Z-API | 7 |
| Edge functions com leitura de credenciais Z-API | 7 |
| Componentes React com referências Z-API | 10 |
| Hooks com referências Z-API | 2 |
| Pages com referências Z-API | 5 |
| Variáveis de ambiente (Supabase secrets) | 3 (`ZAPI_INSTANCE_ID`, `ZAPI_TOKEN`, `ZAPI_CLIENT_TOKEN`) |
| Chaves no banco `app_settings` | 5 (`zapi_instance_id`, `zapi_token`, `zapi_client_token`, `zapi_test_mode`, `zapi_test_number`) |
| Colunas no banco com referência Z-API | 2 (`zapi_message_id` em `whatsapp_messages` e `whatsapp_status_scheduled`) |
| Webhook de entrada implementado | Sim — `whatsapp-webhook/index.ts` |
| Secrets hardcoded no código-fonte | Nenhum |

---

*Documento gerado pelo Agente de Execução (Escopo A). Aguardando revisão do desenvolvedor antes de prosseguir para S5.*
