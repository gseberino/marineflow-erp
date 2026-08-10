# 17 — Integração WhatsApp (Etapa 2, módulo extra)

Superfície: `supabase/functions/_shared/whatsapp/` (factory, evolution-provider, zapi-provider, normalize, types
+ 3 testes Deno), 12 Edge Functions `whatsapp-*`, `src/components/WhatsApp*` (8), `src/components/whatsapp/*` (4),
`src/pages/WhatsApp*` (4), hooks `use-whatsapp-*` (7), `infra/evolution/TUNNEL.md`,
`docs/HANDOFF-EVOLUTION-CUTOVER.md`.

---

## 17.0 Arquitetura real — e a correção do briefing

O briefing descreve "integração WhatsApp via Z-API". **Isso está desatualizado.** O provedor ativo é a
**Evolution API**, com uma camada trocável:

```ts
// supabase/functions/_shared/whatsapp/factory.ts:15-16
export function createWhatsAppProvider(zapiConfig?: Partial<ZapiConfig>): WhatsAppProvider {
  const providerType = Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution";
```
O `ZapiProvider` continua no repositório como implementação alternativa da mesma interface — **não é resíduo
morto**, é a segunda opção da abstração (e o `docs/HANDOFF-EVOLUTION-CUTOVER.md:246` documenta o rollback por
ela). As 15 ocorrências de "zapi" no código ativo são, em sua maioria, nomes de colunas e campos históricos
(`zapi_message_id`) e o próprio provider.

A Evolution roda **na máquina local do dono** (`localhost:8081`), exposta por **Cloudflare Quick Tunnel** com URL
nova a cada reinício (`infra/evolution/TUNNEL.md`). É a dependência de infraestrutura mais frágil do sistema
inteiro — mas é uma decisão de custo consciente, não um defeito de código.

---

## 17.1 Achados

### [MF-AUD-065] Webhook público expondo conversas — ver [MF-AUD-053] (**P0**)
O achado de maior severidade da auditoria está neste módulo: `whatsapp-webhook` responde a `GET` anônimo com o
telefone e o corpo das últimas cinco mensagens recebidas, e executa uma rotina que **deleta** `whatsapp_leads`.
Detalhado no módulo 18.

### [MF-AUD-066] Workers de fila e status invocáveis por qualquer um — ver [MF-AUD-054] (P1)

### [MF-AUD-067] JSDoc da fábrica de provider contradiz o código
- **Módulo:** WhatsApp
- **Arquivo:linha:** `supabase/functions/_shared/whatsapp/factory.ts:5-13` vs `:16`
- **Categoria:** B — **Severidade:** P3
- **Descrição:** O comentário diz `"zapi" (default)`; o código faz
  `Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution"`. Quem ler o JSDoc para depurar um problema de envio vai
  procurar credenciais Z-API. Um comentário errado num ponto de decisão custa mais que a ausência dele.
- **Evidência:**
  ```ts
  // :7-9   * "zapi" (default) — reads credentials from zapiConfig or ZAPI_* env vars.
  // :16    const providerType = Deno.env.get("WHATSAPP_PROVIDER") ?? "evolution";
  ```
- **Ação recomendada:** corrigir o comentário.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-068] `evolution-debug` continua ACTIVE em produção — ver [MF-AUD-055]
A função temporária criada durante o cutover (`docs/HANDOFF-EVOLUTION-CUTOVER.md:119`, `[V-17]`) segue deployada
com `verify_jwt: false`, sem fonte no repositório, desde junho.

---

## 17.2 Verificações feitas que **não** produziram achado

- **Abstração de provider:** interface única (`types.ts`), duas implementações, fábrica por variável de ambiente,
  normalização de telefone isolada (`normalize.ts`) e **três testes Deno**
  (`evolution-provider_test.ts`, `zapi-provider_test.ts`, `normalize_test.ts`). É um dos módulos mais bem
  estruturados do repositório — só não roda em CI (MF-AUD-047).
- **Fila com rate limit:** `whatsapp_send_queue` processada por `whatsapp-queue-worker` com teto por execução,
  teto por hora e atraso entre envios, todos configuráveis em `app_settings`. Proteção contra banimento do
  número — cuidado maduro.
- **Régua e agendamento:** `whatsapp_scheduled_sends`, `whatsapp_status_scheduled`, `whatsapp_templates`,
  `whatsapp_quick_replies`, `whatsapp_blocked_numbers` e `client_whatsapp_settings` cobrem silenciar contato,
  bloquear número e preferência por cliente.
- **Canal interno vs cliente:** as regras que enviam WhatsApp exigem `ai_whatsapp_enabled` **e**
  `phone_normalized` no `app_users` para o canal interno — nunca escorregam para o cliente
  (`task-automations/index.ts:186,325-326`).
- **Identidade de contato:** `resolve_contact_identity` + `unidentified_contacts` + `backfill_message_identity`
  presentes, conforme a Fase 12 do plano `contexto-vivo` (`[V-54]`).

---

*Módulo auditado. 1 achado próprio (`MF-AUD-067`) + 3 referências cruzadas, uma delas P0.*
