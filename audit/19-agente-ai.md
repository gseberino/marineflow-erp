# 19 — Agente AI (Etapa 2, módulo 9)

Superfície: `supabase/functions/_shared/ai/**` (agent.ts, anthropic.ts, prompt.ts, models.ts, autonomy-policy.ts,
context-pruning.ts, intent-router.ts, keyword-resolver.ts, memory-scope.ts, whatsapp-channel.ts, whatsapp-pin.ts,
inbox-detector.ts + `tools/` com 39 arquivos), `supabase/functions/ai-agent/index.ts`, `ai-business-monitor`,
`ai-daily-briefing`, `ai-whatsapp-followups`, `agenda-voice-capture`, `finance-review`, `whatsapp-read-media`;
no frontend, `src/components/ai/*` (6) e `src/hooks/use-ai-agent.ts`.

---

## 20.0 Arquitetura real (e resposta a duas hipóteses do briefing)

**Provedor de LLM — hipótese #8 do briefing: a documentação está errada, o código está certo.**
O runtime **não** usa Gemini via Lovable AI Gateway. Usa **Claude via OpenRouter**:

```ts
// supabase/functions/_shared/ai/anthropic.ts:11,141-142
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const apiKey = Deno.env.get("OPENROUTER_API_KEY");
if (!apiKey) throw new Error("OPENROUTER_API_KEY não configurada no Supabase");
```
```ts
// supabase/functions/ai-agent/index.ts:24
import { callClaude, ClaudeApiError, ... } from "../_shared/ai/anthropic.ts";
```
Modelos citados no código: `anthropic/claude-sonnet-5` (agente) e `anthropic/claude-haiku-4.5`
(`whatsapp-read-media:26`, extração leve). **Nenhuma** referência a `ai.gateway.lovable.dev`, `LOVABLE_API_KEY`
ou `gemini` em `supabase/functions/`. Portanto: `docs/ai-operator-setup.md` (`[V-20]`) descreve a realidade;
`.lovable/plan.md` (`[V-04]`) é histórico e induz ao erro — ver MF-AUD-001.

**Tratamento de erro e retry — hipótese #9 do briefing: o arquivo não existe neste repositório.**
`ai-error.ts`, `classifyAIProviderError` e `fetchAIWithRetry` **não existem** em `Documents/Claude Code/marineflow-erp`.
Existem em `Documents/marineflow-staging` (`supabase/functions/_shared/ai-error.ts` + `src/tests/ai-error.test.ts`)
— a cópia obsoleta, da era Z-API/Lovable. No repositório canônico o papel foi **substituído por um retry
centralizado** dentro de `callClaude`, o que é uma arquitetura melhor: existe **um** ponto de chamada da API, e
todo chamador herda a política.

```ts
// _shared/ai/anthropic.ts:134-138 (doc) e 155-215 (implementação)
const MAX_ATTEMPTS = 3;                       // inicial + 2 retries
// 429/502/503 → retry com backoff, respeitando retry-after
// 400/401     → bug de payload/credencial: loga corpo completo, sem retry
// 402         → créditos insuficientes: erro distinto, sem retry
```
Sobre "o retry permanece desabilitado após o primeiro tool call": **a preocupação não se aplica a esta
arquitetura.** O retry vive *dentro* de `callClaude`, ou seja, antes de qualquer execução de ferramenta — uma
tentativa repetida re-envia o prompt ao modelo, nunca re-executa uma tool já executada. O loop de ferramentas
(`runAgentLoop`, `_shared/ai/agent.ts`) roda por fora e não tem retry próprio.

**Proteção contra o teto de parede da Edge Function:** implementada e documentada —
`timeBudgetMs` padrão de 100 s contra o limite de ~150 s (`agent.ts:59-62`: *"estourar devolve 546 e joga fora
TODO o trabalho já pago"*), o que endereça o incidente registrado em
`plans/marineflow-llm-orquestra-codigo-executa.md` (`[V-63]`).

**Modelo de permissão das tools** (`_shared/ai/tools/registry.ts:9-56`), bem desenhado no papel:
- `ctx.sb` = cliente com o JWT do usuário (**RLS ativa**) — "usar por padrão";
- `ctx.admin` = service role (**bypassa RLS**) — "só usar onde o executor original já usava";
- `roles?: Role[]` filtra quais tools chegam ao modelo por cargo;
- `blockTechnician(ctx)` revalida dentro do `execute()` — defesa em profundidade, necessária porque o canal
  WhatsApp roda com service role;
- `risk: low | medium | high` — `medium`/`high` não executam: gravam `ai_operator_pending_actions` e só rodam
  pelo fluxo determinístico de `confirm_action`.

**Volumetria:** **188 tools** em 39 arquivos. Uso de banco: 195 chamadas via `sb` (RLS) contra **60 via `admin`**
(service role). 16 tools declaram `risk: "high"`.

---

## 19.1 Achados

### [MF-AUD-031] 16 tools usam service role sem nenhuma restrição de cargo
- **Módulo:** Agente AI + Segurança
- **Arquivo:linha:** varredura de `supabase/functions/_shared/ai/tools/*.ts` (lista completa na evidência)
- **Categoria:** F — **Severidade:** P1
- **Descrição:** O contrato do `registry.ts` estabelece três camadas de defesa — RLS via `sb`, filtro `roles[]`,
  e `blockTechnician()` no corpo. Dezesseis tools escapam das três ao mesmo tempo: usam `ctx.admin`
  (service role, sem RLS), **não** declaram `roles` e **não** chamam `blockTechnician`. Como o filtro por cargo é
  o que decide quais tools são oferecidas ao modelo, essas 16 são oferecidas a **todos** os cargos, incluindo
  `technician` — em contradição direta com a regra que o próprio system prompt enuncia ("TECHNICIAN não deve
  acessar preços, financeiro, produtos ou configurações", `registry.ts:24-26`).

  As de `risk: "high"` (três de WhatsApp) ainda param no gate de aprovação. As de `risk: "low"` **executam
  direto**:
  ```
  reports.ts        get_financial_dre            risk=low   ← DRE completo (receivables + payables)
  financial.ts      get_technician_commissions   risk=low   ← comissões
  products.ts       adjust_inventory             risk=low   ← ESCRITA destrutiva em estoque
  bi.ts             get_task_metrics             risk=low
  comms-tools.ts    interpret_customer_reply     risk=low
  memory.ts         forget_note                  risk=low
  service-orders.ts create_service_order         risk=low
  service-orders.ts update_service_order_status  risk=low
  whatsapp.ts       cancel_scheduled_whatsapp / schedule_self_reminder /
                    list_unanswered_messages / mute_contact / unmute_contact   risk=low
  whatsapp.ts       send_collection_reminder / send_service_order_link /
                    schedule_whatsapp_message                                  risk=high (gate ativo)
  ```
  Um técnico logado pode perguntar ao assistente "qual foi o DRE deste mês?" e receber o resultado — sem passar
  por RLS, sem gate, sem registro de cargo. Compare com `overview.ts:26`, que faz certo:
  `roles: NON_TECHNICIAN_ROLES`.
- **Evidência:** varredura programática (bloco por bloco de `name:` até o próximo, testando presença de
  `admin.from|admin.rpc|ctx.admin`, `roles:` e `blockTechnician(`) sobre os 37 arquivos de tools: **188 tools
  detectadas, 16 sem nenhuma das duas proteções**. Contraste:
  ```ts
  // reports.ts:5-19 — sem roles, sem blockTechnician, service role
  name: "get_financial_dre", … risk: "low",
  const { data: rec } = await admin.from("receivables").select("amount, cost_centers(name, type)")…
  const { data: pay } = await admin.from("payables").select("amount, cost_centers(name, type)")…
  ```
  ```ts
  // overview.ts:16-26 — o padrão correto
  name: "get_situation_overview", … risk: "low", roles: NON_TECHNICIAN_ROLES,
  ```
- **Ação recomendada:** classificar as 16 uma a uma (algumas são legítimas para técnico —
  `create_service_order`, `update_service_order_status`), aplicar `roles`/`blockTechnician` às demais, e
  acrescentar um **teste de guarda** que falhe quando uma tool nova usar `ctx.admin` sem declarar `roles` ou
  chamar `blockTechnician`. O teste é mais valioso que a correção pontual: o conjunto cresceu de 63 para 188
  tools em três semanas.
- **Esforço:** M — **Decisão do Gustavo:** Sim — confirmar a matriz cargo × tool para os casos ambíguos
  (o técnico pode ver as **próprias** comissões? pode criar OS pelo chat?).

### [MF-AUD-032] `adjust_inventory`: escrita destrutiva de estoque sem aprovação, sem cargo e sem autoria
- **Módulo:** Agente AI + Estoque
- **Arquivo:linha:** `supabase/functions/_shared/ai/tools/products.ts:224-252`
- **Categoria:** F/A — **Severidade:** P1
- **Descrição:** Caso mais grave do achado anterior, destacado por ser **escrita** e por perder o rastro:
  1. `risk: "low"` → executa direto, sem passar pelo gate de `ai_operator_pending_actions`;
  2. `execute(args, { admin })` → service role, RLS ignorada;
  3. sem `roles`, sem `blockTechnician` → disponível a qualquer cargo;
  4. o `INSERT` em `inventory_movements` **não grava quem fez** — sem `created_by`, sem `user_id`. O ajuste fica
     indistinguível de um movimento do sistema.

  O produto tem histórico documentado de sofrimento com estoque fantasma (memória
  `project_marineflow_estoque_ledger`: R$ 380 mil de estoque criados por estorno sem baixa). Uma tool que
  sobrescreve `stock_quantity` com valor absoluto, sem autoria e sem aprovação, é o mesmo tipo de porta.
- **Evidência:**
  ```ts
  // products.ts:235-249
  risk: "low",
  async execute(args, { admin }) {
    const { product_id, new_quantity, reason } = args;
    const { data: prod } = await admin.from("products").select("stock_quantity").eq("id", product_id).single();
    const delta = new_quantity - (prod?.stock_quantity || 0);
    const { error: updateErr } = await admin.from("products").update({ stock_quantity: new_quantity }).eq("id", product_id);
    if (updateErr) throw updateErr;
    await admin.from("inventory_movements").insert({
      product_id, quantity_delta: delta, movement_type: "manual_adjustment", notes: reason,
    });   // ← nenhum campo de autor
  ```
- **Ação recomendada:** promover para `risk: "high"` (gate de aprovação), restringir a `roles: ['admin','financial']`,
  e gravar `created_by: ctx.userId` no movimento. Verificar de passagem se `inventory_movements` tem coluna de
  autor — se não tiver, é achado de banco (módulo 21).
- **Esforço:** S — **Decisão do Gustavo:** Sim — confirmar que ajuste de estoque pelo chat deve exigir aprovação.

### [MF-AUD-033] Contrato de tools cresceu 3× em três semanas sem revisão de custo
- **Módulo:** Agente AI
- **Arquivo:linha:** 188 tools em `_shared/ai/tools/*.ts` vs `plans/marineflow-ciclo2-fase1-execucao.md:3-5`
- **Categoria:** G — **Severidade:** P2
- **Descrição:** O plano de 22/07 registra "**63 tools** reais, conferidas em 2026-07-21". A contagem hoje é
  **188** — triplicou em três semanas. Cada tool entra no prefixo enviado a cada chamada, e o próprio projeto já
  mediu o custo disso (memória `project_marineflow_otimizacao_tokens`: prefixo de ~69 mil tokens, dos quais ~70 %
  são as definições de tools, com 135 das 188 nunca usadas). Não há, no repositório, nenhum mecanismo que limite
  ou selecione dinamicamente o conjunto — só o filtro por cargo. O `intent-router.ts` existe e poderia servir
  para isso, mas está desligado por decisão registrada (ligá-lo dobraria o custo do jeito que está).
- **Evidência:** contagem programática (188 blocos com `name:` + `risk:`), contra o número declarado no plano.
- **Ação recomendada:** medir antes de agir — instrumentar quais tools são efetivamente chamadas em 30 dias
  (a tabela `ai_operator_audit` provavelmente já tem o dado) e aposentar ou agrupar as que nunca aparecem.
  Macro-tools compostas, como o plano `llm-orquestra-codigo-executa.md` propõe, atacam a causa.
- **Esforço:** M — **Decisão do Gustavo:** Sim — aceitar cortar tools (perda de capacidade teórica) em troca de
  custo por conversa.

### [MF-AUD-034] O system prompt ensina status de OS que o banco rejeita
- Ver **[MF-AUD-007]** no módulo 10 (`_shared/ai/prompt.ts:16-17`). Registrado lá para manter a classe de bug
  junta.

### [MF-AUD-035] A visão "sem próxima ação" do agente ignora OS em `open`
- Ver **[MF-AUD-006]** no módulo 10 (`_shared/ai/tools/overview.ts:159`).

### [MF-AUD-036] Tools que alteram itens de OS não propagam para recebíveis
- Ver **[MF-AUD-009]** no módulo 10 (`recalc_so_totals` sem cascata).

---

## 19.2 Verificações feitas que **não** produziram achado

- **Segredos:** nenhuma chave literal em `supabase/functions/**`. Tudo por `Deno.env.get(...)`
  (`OPENROUTER_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`). O service role nunca aparece no frontend — confirmado que
  `src/**` não referencia `SERVICE_ROLE`.
- **Gate de aprovação:** implementado como desenhado — `risk` medium/high intercepta antes de executar e grava
  `ai_operator_pending_actions`; a execução real passa por `confirm_action`, um caminho determinístico sem
  chamada de LLM. Existe `computeRisk(args)` para risco dependente de argumento (ex.: WhatsApp para equipe =
  medium, para cliente = high). É um desenho acima da média.
- **Defesa em profundidade por cargo:** `blockTechnician` usado em 18 arquivos de tools (73 ocorrências), com o
  motivo documentado (canal WhatsApp roda com service role e não tem RLS de usuário).
- **Cobertura de teste da camada AI:** 10 arquivos `*_test.ts` em `_shared/ai/` (agent, autonomy-policy,
  context-pruning, inbox-detector, intent-router, keyword-resolver, memory-scope, phone, whatsapp-channel,
  whatsapp-pin) + `product-fiscal.test.ts` + testes de tools (`flow-macros_test`, `overview_test`, `so-ops_test`).
  É a área de Edge Function **mais** testada — contrasta com o resto (módulo 18).
- **Desambiguação automática:** `AUTO_DISAMBIG` (agent.ts:80-105) cobre 4 tools de busca e documenta por que
  `list_service_orders` foi deliberadamente excluída. Decisão consciente, registrada no código.

---

*Módulo 9 auditado. 3 achados próprios (`MF-AUD-031`..`MF-AUD-033`) + 3 referências cruzadas. Hipóteses #8 e #9
do briefing respondidas.*
