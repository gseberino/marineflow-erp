# 18 — Supabase Edge Functions (Etapa 2, módulo 8)

Superfície: 36 funções em `supabase/functions/` + `_shared/` (146 arquivos, 31.503 linhas), `supabase/config.toml`,
e **o estado real do projeto em produção** (`okurngvcodmljjicopdp`) via `list_edge_functions` e `cron.job`.

> Método: como no módulo 20, confrontei o repositório com o deploy real. Só leitura.

---

## 18.0 Panorama

| | |
|---|---:|
| Funções no repositório | 36 |
| Funções **deployadas e ACTIVE** em produção | **46** |
| Deployadas **sem fonte no repositório** | **10** |
| Funções com `verify_jwt = false` | 19 (config) |
| Jobs de cron ativos | 17 |
| Funções com CORS `Access-Control-Allow-Origin: *` | 36 |
| Arquivos de teste Deno | 23 (nenhum roda automaticamente — MF-AUD-047) |

---

## 18.1 Achados

### [MF-AUD-053] `whatsapp-webhook` é público e expõe conteúdo de conversas — e apaga registros por GET
- **Módulo:** Edge Functions / WhatsApp / Segurança
- **Arquivo:linha:** `supabase/functions/whatsapp-webhook/index.ts:81-175`; `supabase/config.toml` (`verify_jwt = false`);
  deploy confirmado: `slug: whatsapp-webhook, version: 46, status: ACTIVE, verify_jwt: false`
- **Categoria:** F — **Severidade:** **P0**
- **Descrição:** A função roda com `verify_jwt = false` (necessário: a Evolution API precisa poder chamá-la) e
  **não valida nada** — nem token, nem assinatura, nem origem. O handler aceita `GET` e faz duas coisas graves:

  1. **`GET ?healthcheck=1` devolve conteúdo de mensagens reais de clientes.** A resposta inclui
     `last_message_preview: { phone, body }` e `recent_messages: [{ at, phone, type, body } × 5]` — telefone e
     **texto integral** das últimas cinco mensagens recebidas. Sem autenticação de espécie alguma.
  2. **`GET` sem parâmetro executa a rotina de "limpeza de leads fantasmas", que DELETA linhas de
     `whatsapp_leads`** (`admin.from("whatsapp_leads").delete().eq("id", l.id)`), usando service role. Uma
     operação destrutiva disparável por qualquer requisição GET anônima.

  A URL é trivialmente adivinhável: o padrão é
  `https://<project-ref>.supabase.co/functions/v1/whatsapp-webhook`, e o `project-ref` está no bundle público
  (`VITE_SUPABASE_URL`). Não é preciso credencial nenhuma.

  Compare com os outros webhooks do mesmo projeto, que **fazem certo**: `pluggy-webhook` valida token na query
  contra `PLUGGY_WEBHOOK_TOKEN` e **rejeita tudo** se o secret estiver ausente (`:4-7,41`); `fiscal-webhook`
  valida assinatura HMAC (`x-fiscal-signature`, `:53-55`); `submit-signature` valida `share_token`.
  O `whatsapp-webhook` é a exceção.
- **Evidência:**
  ```ts
  // supabase/functions/whatsapp-webhook/index.ts:81-93 — nenhuma checagem antes do GET
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, …);
    // --- MODO FAXINA E BLINDAGEM (GET) ---
    if (req.method === "GET") {
      const url = new URL(req.url);
      if (url.searchParams.get("healthcheck") === "1") { …
  ```
  ```ts
  // :139-149 — o vazamento
  last_message_preview: lastMsg ? { phone: lastMsg.phone_normalized, body: lastMsg.body, … } : null,
  recent_messages: (recentMsgs || []).map((m) => ({ at: m.created_at, phone: m.phone_normalized,
                                                    type: m.message_type, body: m.body, … })),
  ```
  ```ts
  // :157-173 — a deleção sem autenticação
  console.log("[Cleanup] Iniciando limpeza de leads fantasmas...");
  const { data: leads } = await admin.from("whatsapp_leads").select("id, phone_normalized");
  … if (!msgCount || msgCount === 0) { await admin.from("whatsapp_leads").delete().eq("id", l.id); count++; }
  ```
  Deploy real: `{"verify_jwt":false,"slug":"whatsapp-webhook","version":46,"status":"ACTIVE"}`.
- **Ação recomendada (Fase 2, primeira da fila):** (1) exigir um segredo compartilhado da Evolution — a Evolution
  suporta cabeçalho customizado no webhook; comparar com um secret e responder 401 quando faltar; (2) **remover
  os dois caminhos `GET`** (healthcheck e faxina) ou movê-los para uma função com `verify_jwt = true`; (3) se o
  healthcheck for útil ao dono, mantê-lo devolvendo só contadores e timestamps — nunca telefone e corpo.
  Enquanto não for corrigido, considerar que qualquer pessoa pode ler as últimas mensagens recebidas.
- **Esforço:** S — **Decisão do Gustavo:** Não para corrigir (é P0). Sim apenas para escolher entre remover ou
  proteger o healthcheck.

### [MF-AUD-054] Dois workers de WhatsApp são invocáveis por qualquer pessoa
- **Módulo:** Edge Functions / WhatsApp
- **Arquivo:linha:** `supabase/functions/whatsapp-queue-worker/index.ts:38-45`,
  `whatsapp-status-worker/index.ts`; `supabase/config.toml` (ambas `verify_jwt = false`)
- **Categoria:** F — **Severidade:** P1
- **Descrição:** Das 19 funções com `verify_jwt = false`, 12 validam `CRON_SECRET`/`cron_worker_secret`, e as
  demais validam token, assinatura ou `share_token`. **Duas não validam nada**: `whatsapp-queue-worker` (cron a
  cada minuto, processa a fila e **envia mensagens de verdade** a clientes) e `whatsapp-status-worker`. Qualquer
  requisição anônima dispara o processamento da fila: mensagens saem fora da janela prevista e o limite por hora
  (`whatsapp_queue_max_per_hour`, default 60) pode ser exaurido de propósito, derrubando os envios legítimos.
  O rate limit interno limita o estrago, mas não é controle de acesso.
- **Evidência:** `grep` por `CRON_SECRET|cron_worker_secret|AI_INTERNAL_SECRET|signature|hmac|token` nas 19
  funções com `verify_jwt=false` → só estas duas ficam sem nenhuma checagem. Início do handler
  (`whatsapp-queue-worker/index.ts:38-45`): `Deno.serve` → `OPTIONS` → cria client com service role → executa.
- **Ação recomendada:** aplicar a mesma validação de `x-cron-secret` que as outras 12 funções já usam. É
  copiar-colar de um padrão existente no próprio repositório.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-055] Dez funções rodando em produção sem fonte no repositório
- **Módulo:** Edge Functions / governança
- **Arquivo:linha:** comparação entre `ls supabase/functions` (36) e `list_edge_functions` (46)
- **Categoria:** J/C — **Severidade:** P1
- **Descrição:** Dez funções estão **ACTIVE em produção** e não têm código no repositório canônico. Os
  `entrypoint_path` denunciam a origem — pastas que não existem mais ou diretórios temporários de build:
  ```
  ai-cost-reconcile            v2   /tmp/user_fn_…/source/supabase/functions/ai-cost-reconcile/index.ts
  ai-operator-core             v56  /tmp/user_fn_…/source/index.ts
  ai-operator-gateway          v21  file:///MarineFlow-Integ/ai-operator/…
  ai-lifecycle-hooks           v34  /tmp/user_fn_…/source/index.ts
  ai-feedback                  v30  /tmp/user_fn_…/source/index.ts
  ai-inbound-channel           v27  /tmp/user_fn_…/source/index.ts
  evolution-debug              v24  file:///PC/marineflow-erp/supabase/functions/evolution-debug/index.ts
  evolution-configure-webhook  v25  /tmp/user_fn_…/source/index.ts
  scheduling-automations       v26  file:///Users/PC/…/supabase/functions/scheduling-automations/index.ts
  zapi-configure-webhook       v29  file:///AI-State/.gemini/antigravity/scratch/…
  ```
  Três casos merecem destaque:
  - **`ai-cost-reconcile` tem cron ativo** (`40 * * * *`, confirmado em `cron.job`) — ou seja, **código sem
    fonte versionada roda de hora em hora em produção**. Não é possível auditá-lo, revisá-lo ou reconstruí-lo.
  - **`scheduling-automations`** é a função que o plano `marineflow-agenda-tarefas.md` declara **apagada**
    (`[V-25]`, "apagar `scheduling-automations` (morta)"). Foi removida do repositório, mas **continua ACTIVE**
    em produção, na versão 26. O plano registra uma verdade que só vale para metade do sistema.
  - **`evolution-debug`** é exatamente a função temporária que o `docs/HANDOFF-EVOLUTION-CUTOVER.md:119` mandava
    criar para capturar payload bruto durante o cutover (`[V-17]`), com o passo "4.5 — Reapontar para produção"
    depois. O reapontamento foi feito; a **função de debug ficou ACTIVE, com `verify_jwt: false`**, desde junho.
  - `zapi-configure-webhook` é resíduo do provedor anterior, com entrypoint num diretório de scratch de outra
    ferramenta.
- **Evidência:** as duas listagens; `cron.job` mostrando `ai-cost-reconcile | 40 * * * * | active=true`.
- **Ação recomendada:** classificar as dez em (a) **apagar do projeto Supabase** — `zapi-configure-webhook`,
  `evolution-debug`, `scheduling-automations`, e provavelmente as cinco `ai-operator-*`/`ai-*` dormentes;
  (b) **recuperar a fonte e versionar** — `ai-cost-reconcile`, que está viva e agendada. Verificar antes, com
  `get_edge_function`, o que cada uma faz. **Nada disso pode ser feito sem autorização explícita** (é alteração
  em produção).
- **Esforço:** M — **Decisão do Gustavo:** Sim — autorizar a remoção, uma a uma. E decidir o que fazer com
  `ai-cost-reconcile` (recuperar o código do deploy e commitá-lo é o mínimo).

### [MF-AUD-056] CORS `*` em todas as 36 funções, inclusive nas que aceitam JWT de usuário
- **Módulo:** Edge Functions
- **Arquivo:linha:** 36 arquivos `supabase/functions/*/index.ts` com
  `"Access-Control-Allow-Origin": "*"`
- **Categoria:** F — **Severidade:** P3
- **Descrição:** Todas as funções respondem com CORS totalmente aberto. Para webhooks é irrelevante (não há
  navegador envolvido). Para as chamadas pelo app com JWT do usuário — `ai-agent`, `fiscal-emit`,
  `process-nfe-xml`, `client-portal` — significa que qualquer página web pode chamá-las a partir do navegador de
  um usuário logado. O risco concreto é baixo porque o Supabase exige o `Authorization: Bearer` explícito (não é
  cookie, então não há CSRF clássico), mas é superfície gratuita.
- **Evidência:** `grep -rln 'Access-Control-Allow-Origin.*\*' supabase/functions/*/index.ts | wc -l` → 36.
- **Ação recomendada:** restringir a origem ao domínio do app (`hbrmarine.online` / `*.vercel.app`) nas funções
  chamadas pelo frontend; manter `*` só nos webhooks.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-057] Deploy manual, sem CI — e um workflow que registra o próprio abandono
- **Módulo:** Edge Functions / processo
- **Arquivo:linha:** `.github/workflows/deploy-edge-functions.yml:1-16`
- **Categoria:** I — **Severidade:** P2
- **Descrição:** O único workflow do repositório está desligado, e o cabeçalho explica: falhava em todo push por
  falta dos segredos `SUPABASE_ACCESS_TOKEN`/`SUPABASE_PROJECT_ID`. A consequência aparece nos achados acima:
  quando o deploy é manual, o repositório e a produção divergem (dez funções órfãs, `scheduling-automations`
  "apagada" mas viva). Complementa MF-AUD-043 (não há CI de teste/typecheck).
- **Evidência:** `.github/workflows/deploy-edge-functions.yml:3-16` (comentário + `on: workflow_dispatch`).
- **Ação recomendada:** configurar os dois segredos e religar o `push`, ou assumir o deploy manual e adotar uma
  conferência periódica `list_edge_functions` × `ls supabase/functions`.
- **Esforço:** S — **Decisão do Gustavo:** Sim — criar os segredos no GitHub exige acesso dele.

---

## 18.2 Verificações feitas que **não** produziram achado

- **Autenticação de cron:** 12 funções validam `CRON_SECRET`/`cron_worker_secret` — o padrão está estabelecido e
  documentado no `config.toml` ("só x-cron-secret. Com verify_jwt=true o gateway barraria o cron antes do código").
- **`ai-agent` com `verify_jwt=false`:** intencional e explicado no `config.toml:25-28` — a chamada interna do
  canal WhatsApp é validada contra `AI_INTERNAL_SECRET`; o gateway barraria antes do código. O `index.ts:500`
  ainda checa `OPENROUTER_API_KEY` e a função valida JWT por dentro quando vem do painel.
- **Segredos:** nenhum literal em `supabase/functions/**` — tudo via `Deno.env.get`.
- **`pluggy-connect-token` mantém `verify_jwt = true`** de propósito, com o motivo comentado no `config.toml:89`
  (é a função que emite credencial). Decisão correta e documentada.
- **`banking-reconcile` com `verify_jwt=false` e auth dupla** (JWT do usuário **ou** cron secret) — conforme
  `[V-43]`; verificado no código.
- **Retry/erro do provedor de LLM:** centralizado em `_shared/ai/anthropic.ts` — ver módulo 19.
- **Crons órfãos:** nenhum. Os 17 jobs ativos apontam para funções existentes (ainda que uma delas,
  `ai-cost-reconcile`, só exista no deploy — MF-AUD-055).

---

*Módulo 8 auditado. 5 achados (`MF-AUD-053`..`MF-AUD-057`), sendo **1 P0** e **2 P1**.*
