# Novos achados encontrados durante a Fase 2

Itens fora do escopo da tarefa em execução, registrados conforme a regra 5 da fila.
Não foram corrigidos.

---

## BACKLOG (registrado a pedido do dono, sem implementar)

### Tool de notificação operacional para o técnico, com template fixo
- **Origem:** decisão do dono sobre NOVO-005 (10/08/2026), ao negar WhatsApp livre ao técnico.
- **Ideia:** o técnico não dispara nem agenda mensagem pelo assistente — mas há casos operacionais legítimos
  ("estou a caminho", "cheguei", "serviço concluído") que hoje ou passam por outra pessoa ou não acontecem.
  Uma tool futura poderia cobrir isso com **template fixo e sem texto livre**: o técnico escolhe o evento, o
  sistema monta a mensagem, e não há campo onde ele escreva o que quiser.
- **Por que isso muda o risco:** o problema de dar WhatsApp ao técnico não é o envio — é o **texto livre** para
  cliente, sem revisão. Template fixo remove essa superfície e mantém a rastreabilidade.
- **Referências no código:** já existe `OnMyWayButton.tsx` (agenda) fazendo algo próximo pela UI, e
  `whatsapp_templates` como tabela de modelos. O caminho provável é reaproveitar os dois.
- **Status:** não implementado, sem prazo. Só entra em execução com pedido explícito.

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

---

## [NOVO-005] 14 tools com service role seguem sem barreira de cargo — fora do escopo da decisão #3

- **Encontrado em:** 10/08/2026, durante a T1.5
- **Categoria:** F — **Severidade sugerida:** P2
- **Descrição:** A T1.5 aplicou a decisão #3 (técnico não vê financeiro) e fechou **todas** as tools que
  tocam as cinco tabelas financeiras. Aproveitando a passagem, também barrei as de gestão que usavam service
  role sem cargo (`get_task_metrics`, `agent_health_report`, `list_pending_pos`, `list_low_stock`,
  `get_os_profitability`, `get_technician_commissions`) e endureci `adjust_inventory`.

  **Sobram 14 tools que usam service role e não têm barreira de cargo alguma**, e eu deliberadamente não
  mexi nelas porque decidir ali seria decidir pelo dono:
  ```
  comms-tools.ts    interpret_customer_reply
  memory.ts         list_memory_notes · forget_note
  service-orders.ts create_service_order · update_service_order_status
  whatsapp.ts       send_collection_reminder(high) · send_service_order_link(high) ·
                    schedule_whatsapp_message(high) · list_scheduled_whatsapp ·
                    cancel_scheduled_whatsapp · schedule_self_reminder ·
                    list_unanswered_messages · mute_contact · unmute_contact
  ```
  Três grupos, com respostas provavelmente diferentes:
  1. **OS de campo** (`create_service_order`, `update_service_order_status`) — parecem legítimas para o
     técnico; é o trabalho dele. Manteria como está.
  2. **Lembrete pessoal** (`schedule_self_reminder`, `list_memory_notes`) — idem.
  3. **Comunicação com cliente** (as 8 de WhatsApp, `interpret_customer_reply`) — **aqui é decisão de
     negócio**: o técnico pode disparar mensagem ao cliente pelo agente? As três de `risk: "high"` já param
     no gate de aprovação; as `low` executam direto.
- **Pergunta para o Gustavo:** o cargo técnico pode enviar/agendar WhatsApp para cliente pelo assistente?
  Se não, aplico `NON_TECHNICIAN_ROLES` nas oito de WhatsApp — é o mesmo diff das outras.
- **Evidência:** varredura em `audit/`-scratch reproduzida no teste de guarda
  `supabase/functions/_shared/ai/tools/cargo-financeiro_test.ts`, que hoje cobre só a fatia financeira.

---

## [NOVO-006] Valores da OS continuam visíveis ao técnico — column-level grant não serve aqui

- **Encontrado em:** 10/08/2026, na T1.7 (decisão #3, item 2: "avaliar column-level grants")
- **Categoria:** F — **Severidade sugerida:** P2 · **Status:** avaliado, **não aplicado**, por decisão técnica
- **Descrição:** A decisão #3 pediu para avaliar `REVOKE SELECT (coluna)` nos campos de valor de
  `service_orders` (`grand_total`, `labor_cost_total`, `parts_cost_total`, `travel_cost_total`,
  `operational_cost_total`, `card_fee_amount`, `discount_amount`, `tax_amount`…), com a instrução de manter a
  ocultação atual se quebrasse o frontend. **Quebra.** Motivo:

  1. Column-level grant no Postgres **não omite a coluna** — ele **recusa a consulta inteira** com
     `42501: permission denied for column`. Não existe "devolver NULL no lugar".
  2. O PostgREST expande `select=*` para a lista de colunas. O frontend pede `*` em praticamente todo lugar —
     `SO_SELECT` e `SO_DETAIL_SELECT` (`src/hooks/use-service-orders.ts:15-33`) começam com `*`, e o mesmo
     vale para `usePDFData`/`fetchPDFData`.
  3. Resultado: o técnico deixaria de conseguir **abrir a OS**, que é a tela do trabalho dele. Trocaria um
     problema de confidencialidade por um de operação.

  **O que funcionaria, se um dia virar prioridade:** uma view `service_orders_tecnico` sem as colunas de
  valor + RLS que direcione o técnico a ela, ou uma coluna calculada que zere valores por cargo. As duas são
  mudanças de superfície de API, com impacto no frontend — tarefa própria, não um `REVOKE`.

  **Situação atual, dita sem eufemismo:** o técnico **vê os valores da OS** (total, mão de obra, peças) na
  tela de OS e no PDF. O que a T1.7 fechou foi o acesso às cinco tabelas financeiras — títulos, pagamentos,
  contas a pagar, notas e extrato bancário. É menos do que "não enxerga nada financeiro" ao pé da letra, e o
  Gustavo precisa saber disso para decidir se quer a tarefa da view.
- **Evidência:** `src/hooks/use-service-orders.ts:15-33` (selects com `*`); comportamento documentado do
  PostgREST/Postgres para grants de coluna.
