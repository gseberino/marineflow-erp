# Tabela de Equivalência Z-API → Evolution API v2 (Fase B2)
**Projeto:** MarineFlow ERP — Migração WhatsApp
**Insumo:** `auditoria-zapi.md` (S2/S3), documentação Evolution API v2
**Data:** 2026-06-10

> ⚠️ **Nota de verificação:** o site oficial `doc.evolution-api.com` bloqueia fetch automatizado (HTTP 403). Os payloads abaixo foram confirmados a partir de: documentação oficial (consulta manual), Postman público da Evolution v2.0/v2.2.2, manual de integração comunitário e o repositório `EvolutionAPI/evolution-api`. **Antes de codar o `EvolutionProvider` (B5), validar cada payload contra a instância real provisionada na S5** (a versão `:latest` da imagem pode diferir em detalhes — ver "Gotcha de versão" ao final). Fontes ao final do documento.

---

## Autenticação

| | Z-API | Evolution v2 |
|---|-------|-------------|
| Mecanismo | Credencial embutida na **URL**: `https://api.z-api.io/instances/{INSTANCE_ID}/token/{TOKEN}` + header opcional `Client-Token` | Header **`apikey: <chave>`** em todas as requisições |
| Tipos de chave | `instance_id` + `token` (+ `client_token` de segurança) | **Global** (`AUTHENTICATION_API_KEY` do `.env` — gestão de instâncias) e **por instância** (`hash` retornado no create — mensagens). A global funciona para tudo. |
| Identificação da instância | Embutida na URL (`INSTANCE_ID`) | Nome da instância **no path**: `/message/sendText/{instance}` |

**Mapeamento:** `EVOLUTION_API_KEY` (header `apikey`) substitui `INSTANCE_ID`+`TOKEN`+`Client-Token`. `EVOLUTION_INSTANCE` (nome) substitui o `INSTANCE_ID` da URL.

---

## Tabela de Equivalência

| Capacidade | Z-API (artefato S2) | Evolution v2 (confirmado) | Diferenças de payload | Gotchas / armadilhas |
|---|---|---|---|---|
| **Enviar texto** | `POST {base}/send-text`<br>`{ phone, message }`<br>resp: `{ messageId \| id }` | `POST /message/sendText/{instance}`<br>header `apikey`<br>`{ "number": "55...", "text": "..." }`<br>resp: `{ key:{ id, remoteJid, fromMe }, message, messageTimestamp }` | `phone`→`number`; `message`→`text`; resp `messageId`→**`key.id`** | ID de mensagem muda de nível (`.messageId` → `.key.id`). Campos extras opcionais: `delay`, `linkPreview`. |
| **Enviar PDF/documento** | `POST {base}/send-document/pdf`<br>`{ phone, document(URL), fileName, caption }` | `POST /message/sendMedia/{instance}`<br>`{ "number","mediatype":"document","mimetype":"application/pdf","media": <URL ou base64>,"fileName","caption" }`<br>resp: igual ao sendText | `document`→`media`; **novo campo obrigatório `mediatype:"document"`**; **`mimetype` recomendado**; `fileName` mantém | `media` aceita **URL** (arquivos grandes) **ou base64** (<3MB). Como o MarineFlow já sobe o PDF para o Storage e passa URL pública, **usar URL** (mesmo modelo de hoje). Sem `mediatype`, a Evolution não sabe que é documento. |
| **Enviar link (preview)** | `POST {base}/send-link`<br>`{ phone, message, linkUrl, title, linkDescription, image? }` | **Não há endpoint dedicado.** Usar `sendText` com `linkPreview: true` | Evolution gera o preview a partir da própria URL no texto | **Sem controle de `title`/`linkDescription`/`image` customizados.** O preview é o que o WhatsApp extrair da URL. **Decisão necessária:** no Evolution, o modo "link" do `SendViaZAPIDialog` vira `sendText(message + "\n" + url)` com `linkPreview:true`. Perda de customização de título/imagem do card. ⚠️ Ver "Diferenças e riscos". |
| **Enviar status (stories)** | `/send-text-status`, `/send-image-status`, `/send-video-status` | `POST /message/sendStatus/{instance}`<br>`{ "type":"text\|image\|video", "content","caption?","backgroundColor?","font?","statusJidList?" }` | Três endpoints viram **um** com campo `type` | Pode exigir `statusJidList` (lista de destinatários do status) em algumas versões. **Baixa prioridade** — `whatsapp-status-worker` é recurso secundário; validar só se for migrar status. |
| **Verificar número** | *(não usado no código atual; S2 não encontrou call site ativo)* | `POST /chat/whatsappNumbers/{instance}`<br>`{ "numbers": ["55..."] }`<br>resp: `[{ "exists":bool, "jid", "number" }]` | Recebe **array**, devolve **array** | ⚠️ **Risco de banimento** (issue #2228): checar muitos números em lote pode banir a conta. Usar com parcimônia / um por vez. `checkNumberExists` deve extrair `[0].exists`. |
| **Autenticação** | URL embutida + `Client-Token` | header `apikey` | ver seção acima | Nunca colocar `apikey` no front. Fica em Supabase secrets. |
| **Webhook de entrada (shape)** | Campos planos: `type/event`, `phone`, `messageId/id`, `text.message`, `image/audio/video/document`, `fromMe`, `senderName`, `status`, `ids[]`, `isGroup` (ver S3) | Envelope: `{ event:"messages.upsert", instance, data:{ key:{ remoteJid, id, fromMe }, message:{ conversation \| extendedTextMessage.text \| imageMessage \| documentMessage ... }, pushName, messageTimestamp } }` | **Estrutura totalmente diferente** (aninhada em `data` + `key`). `phone`→`data.key.remoteJid` (com sufixo `@s.whatsapp.net`); `messageId`→`data.key.id`; texto→`data.message.conversation`; nome→`data.pushName`; `fromMe`→`data.key.fromMe`; status (delivery) vem em **evento separado** `messages.update` | **MAIOR RISCO DA MIGRAÇÃO.** Detalhes abaixo. |
| **Configurar webhook** | `POST {base}/update-webhook-{received,delivery,message-status,receive-by-me,disconnected}` (5 chamadas) | `POST /webhook/set/{instance}` (1 chamada)<br>`{ "webhook": { "enabled":true, "url","webhookByEvents":false,"webhookBase64":false,"events":["MESSAGES_UPSERT","MESSAGES_UPDATE","CONNECTION_UPDATE"] } }` | 5 endpoints → **1**; lista de eventos por array | ⚠️ **`webhookByEvents`**: se `true`, a Evolution **acrescenta o nome do evento à URL** (`/webhook/messages-upsert`). Manter **`false`** para receber tudo na mesma rota. ⚠️ Formato do body varia entre versões (v2.0 plano vs v2.2.x aninhado em `webhook`) — confirmar na instância da S5. |
| **Estado da conexão** | *(indireto: instância "conectada")* | `GET /instance/connectionState/{instance}`<br>resp: `{ instance: { state: "open"\|"connecting"\|"close" } }` | — | `state:"open"` = conectado. `"close"` = desconectado → mapear para `error:'instance_disconnected', retryable:false` no `sendText`. |
| **Criar instância** | painel Z-API (manual) | `POST /instance/create`<br>`{ "instanceName","integration":"WHATSAPP-BAILEYS" }`<br>resp: `{ hash, qrcode.base64 }` | — | O `hash` é o token por instância. QR vem em base64. (Coberto pela S5/README.) |
| **Conectar / QR** | painel Z-API | `GET /instance/connect/{instance}` → QR base64 | — | QR expira; gerar novo se necessário. |

---

## Detalhe crítico: webhook de entrada (mapa campo a campo)

Tradução que o `EvolutionProvider.parseIncomingWebhook` deve fazer (Evolution → `IncomingMessageEvent` canônico):

```
Evolution (event "messages.upsert")          →  IncomingMessageEvent canônico
─────────────────────────────────────────────────────────────────────────────
payload.data.key.remoteJid (".../@s.whatsapp.net")  → from  (após normalizePhoneNumber, retirar @s.whatsapp.net e @g.us)
payload.data.key.id                                  → messageId
payload.data.key.fromMe (boolean)                    → fromMe   (ignorar/!processar se true, paridade c/ Z-API)
payload.data.message.conversation
  ?? payload.data.message.extendedTextMessage.text   → text   (null se for mídia pura)
payload.data.message.imageMessage.caption            → text (+ messageType="image", mediaUrl)
payload.data.message.documentMessage.{fileName,caption} → messageType="document"
payload.data.pushName                                → senderName
Number(payload.data.messageTimestamp) * 1000         → timestamp (Evolution dá segundos → ms)
payload.event !== "messages.upsert"                  → return null (ignorar CONNECTION_UPDATE, etc.)
remoteJid termina em "@g.us"                          → grupo → return null (paridade c/ isGroup)
```

**Status de entrega:** na Z-API vinha como `MessageStatusCallback` no **mesmo** webhook (`status`, `ids[]`). Na Evolution vem no evento **`messages.update`** (estrutura própria). O handler precisa tratar `messages.update` à parte para manter a atualização de `delivery_status` por `zapi_message_id`/`provider_message_id`.

---

## Formato de número (confirmado)

- Evolution **aceita** `5547999999999` (DDI+DDD+número), **sem** `+`, espaços ou `@s.whatsapp.net` no payload de envio.
- O sufixo `@s.whatsapp.net` aparece **apenas** no `remoteJid` das **respostas/webhooks** — deve ser **removido** ao normalizar.
- **9º dígito:** a Evolution/Baileys **não garante** correção automática universal; números BR de celular devem ir com o 9º dígito. → reforça a necessidade da `normalizePhoneNumber` única (risco #7 do B1).

---

## Principais diferenças e riscos

1. **Shape do webhook (CRÍTICO).** A diferença Z-API (plano) × Evolution (`data.key.*` aninhado, timestamp em segundos, `remoteJid` com sufixo, status em evento separado `messages.update`) é o ponto de maior risco. Todo o `parseIncomingWebhook` precisa ser reescrito e coberto por testes (S7, casos 10–11) com payloads **reais** capturados da instância da S5.
2. **`send-link` não tem equivalente direto.** A Evolution não permite customizar título/descrição/imagem do card de link. O modo "link" do `SendViaZAPIDialog` (hoje muito usado para enviar OS/orçamento com card bonito) será **degradado** para `sendText` com `linkPreview:true`. **Decisão de produto necessária** — possível alternativa: enviar como `sendMedia` (PDF) com a URL na legenda, mantendo o link clicável no texto. Recomendo levar ao desenvolvedor (ver pergunta).
3. **ID da mensagem muda de nível** (`.messageId` → `.key.id`). Como hoje o código usa `any`, isso quebraria **silenciosamente** (risco #3 do B1). A coluna `zapi_message_id` passa a guardar o `key.id` da Evolution — renomear conceitualmente para `provider_message_id` (sem migração de schema obrigatória no cutover; pode-se reusar a coluna).
4. **Verificação de número pode banir a conta** se usada em lote. Implementar `checkNumberExists` com cautela (um número por vez, sem varreduras).
5. **Gotcha de versão.** A imagem `evoapicloud/evolution-api:latest` (S5) pode ser v2.0, v2.1 ou v2.2.x. O body do `/webhook/set` e a presença de `mimetype`/`statusJidList` variam entre elas. **Validar contra a instância real antes de fixar o `EvolutionProvider`.**

---

## Fontes

- [Send Plain Text — Evolution API Documentation](https://doc.evolution-api.com/v2/api-reference/message-controller/send-text)
- [Manual de Integração Evolution API V2 (gist)](https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a)
- [Evolution API v2.0 — Postman público](https://www.postman.com/agenciadgcode/evolution-api/documentation/gqr041s/evolution-api-v2-0)
- [Check is WhatsApp Number — Postman v2.2.2](https://www.postman.com/agenciadgcode/evolution-api/request/qmmm1l6/check-is-whatsapp-number)
- [Webhooks — Evolution API Documentation](https://doc.evolution-api.com/v2/en/configuration/webhooks)
- [Issue #1340 — "messages.upsert" no webhook](https://github.com/EvolutionAPI/evolution-api/issues/1340)
- [Issue #2228 — risco de ban em whatsappNumbers](https://github.com/EvolutionAPI/evolution-api/issues/2228)
- [Repositório EvolutionAPI/evolution-api](https://github.com/EvolutionAPI/evolution-api)

> **Fim da Fase B2. Aguardando revisão do desenvolvedor antes de prosseguir para B4.**
