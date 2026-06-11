# Relatório de Riscos — Integração Z-API (Fase B1)
**Projeto:** MarineFlow ERP — Migração WhatsApp Z-API → Evolution API
**Insumo:** `auditoria-zapi.md` (Escopo A, S1–S4)
**Branch:** `claude/keen-brown-j2pgw0`
**Data:** 2026-06-10

> Este relatório avalia o código Z-API **atual** com olhar crítico, **antes** de qualquer mudança. Nenhum comportamento foi alterado nesta fase.

---

## Sumário de severidades

| # | Risco | Severidade |
|---|-------|-----------|
| 1 | Duplicação de envio por falta de idempotência (cobranças/PDF) | **CRÍTICO** |
| 2 | Ausência total de timeout nas chamadas HTTP à Z-API | **ALTO** |
| 3 | Respostas da Z-API tratadas como `any` (sem contrato tipado) | **ALTO** |
| 4 | Normalização de telefone inconsistente (≥4 implementações) | **ALTO** |
| 5 | PDF regenerado e re-enviado a cada tentativa de retry | **ALTO** |
| 6 | Falha silenciosa nos crons (sem alerta/observabilidade) | **MÉDIO** |
| 7 | Credenciais em `app_settings` legíveis pelo front (RLS-dependente) | **MÉDIO** |
| 8 | Acoplamento direto à Z-API em 7 edge functions | **MÉDIO** |
| 9 | Observabilidade inconsistente entre os caminhos de envio | **MÉDIO** |
| 10 | Origem de credenciais inconsistente (env vs DB) | **MÉDIO** |
| 11 | `notifyAssignedReminder` engole erros silenciosamente | **BAIXO** |

---

## 1. Tratamento de erro

**Caminho do usuário (`whatsapp-send` + `useZApiSend`):** ✅ adequado.
- `whatsapp-send/index.ts` tem `try/catch` global, valida com Zod (400), retorna **502** em erro da Z-API e **500** em exceção, e **sempre** grava no `audit_log` (sucesso ou falha) com `zapi_response` e `http_status`.
- `useZApiSend` captura o erro, exibe `toast.error` com a mensagem, e invalida as queries de status/histórico. O usuário **vê** a falha.
- Impacto isolado: a falha de envio **não** impede a criação da cobrança/OS — apenas o WhatsApp falha. Bom desacoplamento de efeito.

**Caminho dos crons (`scheduling-automations`, `whatsapp-queue-worker`, `whatsapp-status-worker`):** ⚠️ falha **silenciosa**.
- Erros são capturados por item e registrados em `console.error` / coluna `failed_reason` / `log[]`, mas **ninguém é notificado**. Uma indisponibilidade prolongada da Z-API só seria descoberta por inspeção manual de logs. → ver risco #6.

**`notifyAssignedReminder` (webhook):** erros engolidos com `console.error` (risco #11). Aceitável por ser notificação best-effort, mas não documentado.

**Conclusão:** o tratamento de erro do caminho interativo é bom; o dos caminhos automáticos é fraco em observabilidade. **Severidade do conjunto: MÉDIO** (puxado pelos crons).

---

## 2. Retry e idempotência — **CRÍTICO**

Existem **duas camadas independentes de retry/fallback**, nenhuma com chave de idempotência:

1. **`useZApiSend.send()`** (`use-zapi-send.ts:82`) — retry exponencial (`min(8000, 1000·2^(n-1))`), até `maxAttempts` (1–5).
2. **`useSendCollectionWhatsApp`** (`use-collections.ts:447-489`) — loop de **fallback de método**: `pdf → text_link → text`. Se um método "falha", tenta o próximo.

### O problema de idempotência

A Z-API `/send-text` e `/send-document` **não recebem nenhuma chave de deduplicação**. Cenário de falha realista:

> A requisição chega à Z-API, a mensagem **é entregue** ao cliente, mas a **resposta se perde** (timeout de rede na volta — agravado pela ausência de timeout, risco #2). O código interpreta como falha e **reenvia**.

Consequências:
- **Cobranças (`billing`):** o cliente recebe a **mesma cobrança duas ou mais vezes**, ou recebe o **PDF E o texto** (porque o fallback `pdf → text_link` dispara após um "falso negativo" do PDF). Dano direto à experiência e à credibilidade.
- **PDF de OS/orçamento:** mesmo risco de documento duplicado.

### Mitigação parcial existente
- O botão do `SendViaZAPIDialog` fica `disabled={sending}`, o que mitiga **duplo clique** na UI — mas **não** mitiga a duplicação por retry/fallback nem chamadas via cron.

### Recomendação
- **Antes do cutover**, introduzir idempotência na camada `WhatsAppProvider` (Fase B4/B5): chave determinística por `(contexto, record_id, hash_da_mensagem)` registrada antes do envio; em retry, consultar antes de reenviar. Alternativamente, **só fazer retry quando o erro for comprovadamente pré-entrega** (ex.: 4xx de validação, recusa de conexão) e **nunca** em timeout de resposta.
- Este é o item que **deve ser resolvido antes da migração** (e idealmente corrigido também no `ZapiProvider` por ser dano ao cliente — ver regra B4.3).

**Severidade: CRÍTICO.**

---

## 3. Timeouts — **ALTO**

Confirmado por varredura (`grep AbortController|AbortSignal|timeout` em `supabase/functions`): **nenhuma** chamada `fetch` à Z-API usa `AbortController` ou qualquer timeout. Os únicos `setTimeout` são o `sleep` do queue-worker e o backoff do hook.

- Sem timeout, uma chamada pendurada à Z-API mantém a edge function ocupada até o limite de wall-clock da plataforma, e a UI fica em "Enviando…" indefinidamente (o spinner do `useZApiSend` só encerra no `finally`, que depende do `fetch` resolver).
- Agrava diretamente o risco #1 (timeout de resposta → retry → duplicação).

**Recomendação:** timeout explícito de **10s por tentativa** via `AbortController` na camada de provider (já previsto em B5 para o `EvolutionProvider`; aplicar conceito também ao `ZapiProvider`).

**Severidade: ALTO.**

---

## 4. Acoplamento — **MÉDIO**

- **7 edge functions** montam a URL `https://api.z-api.io/instances/.../token/...` e chamam `fetch` diretamente, com o shape do payload hardcoded por endpoint. Não há camada intermediária — é exatamente o alvo da Fase B4.
- **Ponto positivo:** o front-end **nunca** chama a Z-API diretamente; sempre passa por edge functions (`supabase.functions.invoke`). O acoplamento é no backend, não no browser.
- **Impacto na UX de um erro Z-API:** isolado — apenas o envio de WhatsApp falha, com toast; o fluxo de negócio (cobrança/OS) permanece íntegro. Bom.

**Severidade: MÉDIO** (dívida arquitetural, sem impacto funcional imediato).

---

## 5. Segredos e segurança — **MÉDIO**

- **Bundle do cliente:** ✅ confirmado — **nenhum** token Z-API hardcoded em `.tsx/.ts/.js`. As `VITE_*` são apenas chaves públicas do Supabase.
- **Origem das chamadas:** ✅ backend (edge functions), não browser.
- **⚠️ Ponto de atenção:** `zapi_token` e `zapi_client_token` ficam em `app_settings` e são lidos por uma **query autenticada do front** (`WhatsAppZApiSettings.tsx:31-34`, `filter key like 'zapi_%'`). O risco depende **inteiramente da RLS de `app_settings`**:
  - Se o `SELECT` estiver liberado para qualquer usuário autenticado → **qualquer conta logada lê os tokens**.
  - **Ação recomendada (verificar antes do cutover):** restringir leitura das chaves `zapi_*` / `evolution_*` a `role = 'admin'` (ou mover credenciais para Supabase secrets e parar de espelhá-las no DB).

**Severidade: MÉDIO** (não é exposição no bundle, mas é exposição potencial via RLS).

---

## 6. Tipagem e contratos — **ALTO**

- As respostas da Z-API são tratadas como **`any`** em todos os pontos: `(zapiBody as any).error`, `(data as any).messageId || (data as any).id`, `zapiRes.messageId || zapiRes.id`, etc.
- **Por que é risco de migração:** a Evolution retorna um shape **diferente** (`key.id`, `key.remoteJid`, `messageTimestamp` — ver `tabela-equivalencia.md`). Como o código acessa campos via `any`, um campo ausente/renomeado **não gera erro de compilação** — vira `undefined` silencioso (ex.: `providerMessageId` nulo, status de entrega nunca casando no dedup do webhook).
- **Normalização de número (sub-item):** inconsistente — ver risco #4.

**Recomendação:** tipar as respostas de cada provider e expor apenas o `SendResult`/`IncomingMessageEvent` canônicos para o resto do sistema (Fase B4.1). Nenhum `any` deve atravessar a fronteira do provider.

**Severidade: ALTO.**

---

## 7. Normalização de telefone — **ALTO** (destacado do item 6)

Foram encontradas **pelo menos 4 implementações divergentes**:

| Local | Regra |
|-------|-------|
| `use-zapi-send.ts:47` | `replace(/\D/g,'')` apenas (sem DDI) |
| `whatsapp-send/index.ts:88-92` | `replace(/\D/g,'')` + swap por `testNumber` se testMode |
| `whatsapp-webhook/index.ts:18-26` (`normalizePhone`) | tira `@`, adiciona `55` se 10/11 dígitos, mantém ≥14 |
| `src/lib/masks.ts:124` (`normalizePhoneE164`) | trata `00`, passthrough se ≥12, prefixa `55` se 10/11 |

O **mesmo número** pode ser enviado com formatações diferentes dependendo do caminho (cobrança via `use-collections` usa `normalizePhoneE164`; teste via `WhatsAppZApiSettings` passa cru; queue-worker usa o `phone_normalized` já gravado). Isso causa: falsos "número inválido", divergência no dedup do webhook, e comportamento imprevisível na Evolution (que exige DDI+DDD).

**Recomendação:** função única `normalizePhoneNumber(raw): string` **compartilhada** entre providers (Fase B4.2), com regra explícita de 9º dígito. Esta é uma pré-condição da migração.

**Severidade: ALTO.**

---

## 8. Observabilidade — **MÉDIO**

- **Bom:** `whatsapp-send` grava `audit_log` rico (provider, kind, phone, preview, `zapi_response`, `http_status`) — permite depurar uma falha sem acesso ao servidor.
- **Ruim:** `whatsapp-send-text`, `whatsapp-queue-worker`, `whatsapp-status-worker` e `scheduling-automations` **não** alimentam o `audit_log` de forma consistente — registram em `console` ou em colunas da própria fila. Uma falha nesses caminhos é muito mais difícil de diagnosticar em produção.
- Não há métrica agregada de taxa de sucesso/erro nem alerta.

**Recomendação:** padronizar o log de envio na camada de provider (um único ponto que grava `audit_log` com `provider`, `ok`, `retryable`, `providerMessageId`, latência). Facilita também a comparação de paridade Z-API × Evolution no cutover (B6).

**Severidade: MÉDIO.**

---

## Itens que DEVEM ser resolvidos antes de prosseguir com a migração

1. **[CRÍTICO] Idempotência de envio (#1, #5).** Projetar deduplicação/política de retry segura na camada de provider antes do cutover; corrigir também no `ZapiProvider` por ser dano direto ao cliente (cobrança duplicada). Conforme regra B4.3, bug crítico que afeta o cliente é exceção à regra de "não corrigir bugs no ZapiProvider".
2. **[ALTO] Timeout (#2)** e **normalização única (#7)** — pré-condições técnicas da Fase B4.2/B5; sem elas, a Evolution herda os mesmos defeitos.
3. **[MÉDIO] Verificar RLS de `app_settings` (#5)** antes de adicionar as chaves `evolution_*`.

Os demais itens (tipagem `any`, observabilidade, acoplamento) são **resolvidos naturalmente** pela introdução da interface `WhatsAppProvider` (B4) e pela implementação tipada do `EvolutionProvider` (B5).

---

## Divergências em relação aos artefatos do Escopo A

Nenhuma contradição encontrada. **Acréscimos** ao inventário do Sonnet:
- O caminho de cobrança `useSendCollectionWhatsApp` (`use-collections.ts:402-499`) tem um **segundo** mecanismo de retry/fallback (`pdf→text_link→text`) **não destacado** como risco em S2 — é central para o risco crítico de idempotência (#1).
- `attemptSend` (`use-zapi-send.ts:63-75`) **regenera e re-faz upload do PDF a cada tentativa** — risco #5, não capturado em S2.
- Existe a função `whatsapp-process-scheduled` que faz *recovery* de itens presos em "processing" (comentário cita "Z-API hang"), o que **confirma** empiricamente o risco de ausência de timeout (#2).

> **Fim da Fase B1. Aguardando revisão do desenvolvedor antes de prosseguir para B4.**
