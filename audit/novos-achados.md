# Novos achados encontrados durante a Fase 2

Itens fora do escopo da tarefa em execução, registrados conforme a regra 5 da fila.
Não foram corrigidos.

---

## [NOVO-001] `deno check`/`deno test` sem `--no-check` falha em qualquer função que importe supabase-js

- **Encontrado em:** T0.1 (MF-AUD-053), ao rodar o gate de teste
- **Categoria:** I (testes/CI) — **Severidade sugerida:** P2
- **Descrição:** `deno test --allow-all supabase/functions/...` aborta antes de executar quando o arquivo sob
  teste importa `https://esm.sh/@supabase/supabase-js@2.45.0`:
  ```
  error: Error: Could not find "@types/node" in a node_modules folder.
  Deno expects the node_modules/ directory to be up to date. Did you forget to run `deno install`?
  ```
  A causa é a presença de `node_modules/` do frontend na raiz: o type-checker do Deno tenta resolver as
  `@types` referenciadas pelo pacote npm e não encontra. Com `--no-check` a suíte roda normalmente
  (**240 testes, 0 falhas**).
- **Por que importa agora:** a tarefa **T2.2** vai colocar `deno test -A supabase/functions` no CI. Do jeito
  que está, ou o comando precisa de `--no-check`, ou o CI quebra em todas as funções que falam com o banco —
  que são quase todas. E usar `--no-check` significa que o CI **não** verifica tipos das Edge Functions, o que
  reabre exatamente o buraco descrito em MF-AUD-046 (o `tsc` do frontend não cobre `supabase/functions`).
- **Sugestão para T2.2:** rodar o teste com `--no-check` **e** acrescentar um passo separado de
  `deno check` com um `deno.json` próprio em `supabase/functions/` (que isole a resolução de tipos do
  `node_modules` do frontend). Assim o CI executa os testes e ainda verifica tipos.
- **Evidência:** saída dos dois comandos, executados em 08/08/2026 no worktree `session/p0-webhook`.

---

## [NOVO-002] Eventos da Evolution ligados sem consumidor no código — e `Webhook Base64` como risco de perda de mensagem

- **Encontrado em:** 09/08/2026, durante a T0.1 (o dono ampliou os eventos no Evolution Manager)
- **Categoria:** G (performance/custo) + A (risco funcional) — **Severidade sugerida:** P2
- **Descrição:** A instância passou a emitir ~18 eventos: `APPLICATION_STARTUP`, `CHATS_SET/UPDATE/UPSERT`,
  `CONNECTION_UPDATE`, `CONTACTS_SET/UPDATE/UPSERT`, `GROUP_UPDATE`, `GROUPS_UPSERT`, `LABELS_ASSOCIATION`,
  `LABELS_EDIT`, `MESSAGES_SET/UPDATE/UPSERT`, `PRESENCE_UPDATE`, `QRCODE_UPDATED`, `SEND_MESSAGE`
  — além de **`Webhook Base64` ligado**.

  O webhook trata explicitamente `messages.update` (status de entrega) e, para o resto, delega a
  `provider.parseIncomingWebhook(payload)`; o que não for mensagem retorna `null` e sai como
  `{ok:true, ignored:"system_or_group"}` (`whatsapp-webhook/index.ts:238-245`). Portanto **todos os eventos
  novos são invocação paga e descartada**.

  Dois riscos, em ordem de gravidade:
  1. **`Webhook Base64`**: faz a Evolution embutir o binário da mídia em base64 no corpo do webhook. O código
     **não lê base64** (`grep -n "base64" whatsapp-webhook/index.ts` → nada); a mídia é obtida por URL em
     `whatsapp-read-media`. Um vídeo de 5 MB vira ~6,7 MB de JSON inútil por requisição, com risco de estourar
     o limite de corpo da Edge Function — e aí **a mensagem com mídia não é gravada**.
  2. **Volume**: `PRESENCE_UPDATE` dispara a cada "digitando"/"online" de qualquer contato; `MESSAGES_SET`,
     `CHATS_SET` e `CONTACTS_SET` mandam sincronização em massa a cada reconexão da instância.
- **Recomendação imediata (config, sem código):** desligar `Webhook Base64` e manter ligados apenas
  `MESSAGES_UPSERT`, `MESSAGES_UPDATE`, `SEND_MESSAGE` e `CONNECTION_UPDATE`.
- **Oportunidade real (vira tarefa quando houver código):**
  - `CONTACTS_UPSERT`/`CONTACTS_UPDATE` → o payload traz `pushName`/nome do contato: alimenta direto a
    identidade de contatos (frente que levou a identificação de 1,1% → 72,6%), sem custo de IA.
  - `CONNECTION_UPDATE` → detectar queda da instância e avisar o dono; hoje a queda só é percebida pelo
    silêncio. Casa com o `health_status` que o healthcheck já calcula.
  - `MESSAGES_DELETE` (hoje desligado) → registrar que o cliente apagou uma mensagem.
- **Evidência:** prints do Evolution Manager (09/08/2026); `whatsapp-webhook/index.ts:238-245`; ausência de
  qualquer referência a base64 na função; logs de Edge Function mostrando `POST | 200` seguidos com
  `?token=` logo após o Save.

---

## [NOVO-004] Nenhum teste cobre os termos e condições do PDF

- **Encontrado em:** 09/08/2026, durante a S3 (diagnóstico do sintoma dos termos)
- **Categoria:** I (testes) — **Severidade sugerida:** P3
- **Descrição:** Existem **sete** arquivos de teste de PDF (`pdf-generator`, `pdf-generator.payment-history`,
  `pdf-canvas-scale`, `pdf-css-isolation`, `pdf-survey`, `pdf-html-isolation`, `pdf-pagination`) e **nenhum**
  menciona `showTerms` ou `terms` — busca em `src/lib/*.test.ts` e `src/test/*.test.ts` retorna vazio.
  Os termos são conteúdo contratual que vai ao cliente, e a parte determinística é trivial de cobrir: dado
  `showTerms: true` e `terms` preenchido, o HTML gerado contém "Condições Gerais e Garantia" e o texto; com
  `showTerms: false`, não contém. Isso não testa a rasterização do `html2canvas` (que exige navegador), mas
  trava a metade do problema que é lógica pura — justamente a metade que o diagnóstico da S3 precisou
  verificar à mão.
- **Ação recomendada:** dois casos em `pdf-generator.test.ts`. Não foi feito por estar fora do escopo da S3
  (somente leitura).
- **Evidência:** `audit/diagnostico-terms.md` §6; `grep -rn "showTerms\|terms" src/lib/*.test.ts src/test/*.test.ts` → vazio.
