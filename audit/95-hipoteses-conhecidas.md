# 95 — Status das 10 hipóteses conhecidas do briefing

Cada uma classificada como **Corrigido / Ainda presente / Parcialmente corrigido / Não localizado**, com
evidência e ponteiro para o achado correspondente.

---

## 1. PDF: `scheduled_start_at` aparece em PDFs de orçamento — deveria aparecer só em `service_order`

**Status: CORRIGIDO (por remoção total) — com pergunta em aberto.**

O campo continua no contrato de dados (`src/lib/pdf-generator.ts:98`) e é preenchido pelos dois construtores
(`use-pdf.ts:129` e `:311`), mas **nenhum dos quatro geradores de HTML o renderiza** — a única ocorrência de
"scheduled" no arquivo de 1.396 linhas é a declaração de tipo. Ou seja, a correção removeu a data agendada do
orçamento **e também da OS**.

→ **[MF-AUD-018]** (P3). Pergunta ao Gustavo: a OS impressa **deveria** mostrar a data agendada?

---

## 2. PDF: termos e condições não renderizam — verificar `app_settings.terms` e o pass-through no PDFData

**Status: PARCIALMENTE ESCLARECIDO — o código está correto; a causa provável é de dado/permissão.**

Três fatos apurados:
1. Não existe a chave `app_settings.terms`. Os termos vêm de **cinco** chaves (`terms_general`,
   `terms_warranty`, `terms_cancellation`, `terms_delivery`, `terms_responsibilities`), concatenadas em
   `use-pdf.ts:219-225`. As cinco são **semeadas com texto padrão** na migration inicial
   (`20260407223837_*.sql:73-89`) e editáveis em `SettingsPage.tsx:31-35`.
2. O pass-through existe e a renderização está correta: `pdf-generator.ts:1155-1158`
   (`${options.showTerms && data.terms ? …}`), com `showTerms: true` no `DEFAULT_PDF_OPTIONS`.
3. **O ponto de falha é outro:** `resolvePdfOptions` lê `app_settings.pdf_options_<tipo>`, e o
   `PDFOptionsDialog` **grava essa chave a cada download/impressão** (`:131-133`), globalmente para toda a
   empresa. Se alguém desmarcou "Termos" uma vez, os termos sumiram para todos, inclusive dos PDFs enviados por
   WhatsApp.

→ **[MF-AUD-014]** (P1). **Verificação de 1 minuto antes da Fase 2:** consultar o valor de
`app_settings.pdf_options_quote` em produção. Se `showTerms` estiver `false`, o mistério está resolvido e a
correção de dado é imediata.

---

## 3. Mobile: overflow nas páginas de lista (Clientes, Embarcações, Marinas), cards poluídos, sem paginação

**Status: CORRIGIDO nas duas gerações da UI.**

- Legadas: `PAGE_SIZE = 20` com paginação (`ClientList.tsx:27,70-71`; `VesselList.tsx:16,70-71`;
  `MarinaList.tsx:26,67-68`) e colunas secundárias escondidas por breakpoint (`hidden md:table-cell`,
  `hidden lg:table-cell`).
- V2 (as servidas hoje): `DataTable` resolve por construção — ResizeObserver mede o contêiner e exibe só as
  colunas que cabem, o resto vai para a linha expansível; wrapper com `overflow-hidden`
  ("nunca aparece barra de rolagem lateral", `src/v2/components/DataTable.tsx:68-76`), mais `PAGE_SIZE = 20`.

→ Sem achado. Ressalva: **os painéis financeiros** (aging, conciliação, reembolsos, importação, edição em massa)
ainda usam tabelas com `min-w-[600..1000px]` dentro de `overflow-x-auto` → **[MF-AUD-052]** (P2).

---

## 4. Agenda: dropdown de OS em branco no dialog de agendamento (`useSchedulableOrders`)

**Status: AINDA PRESENTE — e a causa está identificada com precisão.**

```ts
// src/hooks/use-agenda.ts:163
.in('status', ['draft', 'pending', 'approved', 'scheduled', 'in_progress',
               'waiting_parts', 'waiting_approval', 'reopened'])
```
Contra o CHECK vigente da tabela (`20260422155330_*.sql:3`):
```sql
CHECK (status = ANY (ARRAY['draft','scheduled','open','in_progress','awaiting_parts',
                           'awaiting_client','approved','completed','invoiced','cancelled']))
```
Quatro dos oito status filtrados **não existem** (`pending`, `waiting_parts`, `waiting_approval`, `reopened`) e
três que existem ficam de fora — em especial **`open`**, o status normal de uma OS aberta. O dropdown só enxerga
`draft`, `approved`, `scheduled` e `in_progress`.

→ **[MF-AUD-005]** (P1). A mesma lista fantasma aparece em mais três lugares: **[MF-AUD-006]**
(`overview.ts:159`, a visão do agente), **[MF-AUD-007]** (`prompt.ts:16-17`, o que o modelo aprende) e
**[MF-AUD-008]** (`ServiceOrderTimeline.tsx:48-49`).

---

## 5. Agenda: grid técnico×dia com overflow no mobile

**Status: CORRIGIDO.**

```ts
// src/pages/AgendaPage.tsx:891
// Mobile (< lg): dias empilhados — zero scroll horizontal (Princípio 0)
const mobileDays = days.map((d) => { … });
```
A matriz técnico×dia só é montada a partir de `lg`. A única `grid-cols-N` sem breakpoint é a do calendário
mensal (`:1148`, `grid-cols-7`), semanticamente correta.

→ Sem achado.

---

## 6. Erro de validação UUID ao vincular técnico a uma OS

**Status: CORRIGIDO.**

O formulário tem helper dedicado e o aplica a todos os campos UUID opcionais:
```ts
// src/components/ServiceOrderForm.tsx:803
const uuidOrNull = (v: string | null | undefined) => (v && v.trim() !== '' ? v : null);
```
Os vínculos de técnico filtram strings vazias antes de inserir (`:828`, `:893`), e todos os pontos que gravam
`technician_user_id` usam `|| null` / `|| undefined` (`:874, 1375, 1415, 1481, 1615, 1632`). Nenhum caminho
encontrado que envie `''` para coluna `uuid`.

→ Sem achado sobre UUID. **Mas a auditoria do mesmo trecho encontrou outro defeito**: o salvamento apaga todos os
técnicos e reinsere sem transação e **sem checar erro** — se o insert falhar, a OS fica sem técnico e o usuário
vê "sucesso" → **[MF-AUD-010]** (P2).

---

## 7. Itens do "Prompt #23"

> Nota de rastreabilidade: assim como `MIG-01..08`, **o documento "Prompt #23" não existe em disco**. A busca por
> `prompt #23` / `prompt-23` / `Prompt 23` em `Documents/`, `.claude/` e `Desktop/` só encontra os relatórios
> desta própria auditoria. Os oito itens abaixo foram verificados a partir da descrição do briefing, um a um.

| Item | Status | Evidência |
|---|---|---|
| Hook `useAppUsers` duplicado | **Corrigido** | definição única em `src/hooks/use-app-users.ts:48` |
| `NavLink.tsx` morto | **Corrigido** | arquivo não existe |
| `mock-data.ts` morto | **Corrigido** | arquivo não existe; `src/data/` também não |
| Falta de `staleTime` em hooks estáticos | **Corrigido estruturalmente** | default global `staleTime: 60_000` em `src/lib/query-client.ts`; 34 hooks ainda declaram valor próprio |
| Ausência de hook `useAppSettings` | **Corrigido** | `src/hooks/use-app-settings.ts` exporta `useAppSettings()` e `useAppSetting()` |
| Saudações do Dashboard/Agenda fora do i18n | **Corrigido** | `src/i18n/pt-BR.ts:65` — `greeting: { morning, afternoon, evening }` |
| Dias da semana fora do i18n | **Corrigido** | nenhuma lista hardcoded; `WEEKDAYS = ag.weekdaysShort` (`AgendaPage.tsx:835`) |
| `STATUS_LABELS` hardcoded fora do i18n | **AINDA PRESENTE** | cinco mapas: `ServiceOrderTimeline.tsx:44`, `use-purchase-orders.ts:426`, `use-quote-requests.ts:648`, `pdf-generator.ts:812`, `purchase-needs.ts:245` → **[MF-AUD-029]** |

Adicionalmente encontrado no mesmo espírito: import morto de `usePDFData` em
`src/components/service-order/form-parts.tsx:65` → **[MF-AUD-019]**.

---

## 8. Discrepância de modelo AI: documentação diz Claude, runtime usa Gemini via Lovable AI Gateway

**Status: INVERTIDO — o runtime usa Claude; é a documentação antiga que fala em Gemini.**

```ts
// supabase/functions/_shared/ai/anthropic.ts:11,141
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const apiKey = Deno.env.get("OPENROUTER_API_KEY");
```
Modelos no código: `anthropic/claude-sonnet-5` (agente) e `anthropic/claude-haiku-4.5`
(`whatsapp-read-media:26`). **Nenhuma** referência a `ai.gateway.lovable.dev`, `LOVABLE_API_KEY` ou `gemini` em
`supabase/functions/`.

O documento correto é `docs/ai-operator-setup.md` ("Fase 1: migração para Claude via OpenRouter"). O que induz ao
erro é `.lovable/plan.md:36-37,116-117`, de 25/04/2026, que continua no repositório sem aviso de obsolescência.

→ **[MF-AUD-001]** (P2).

---

## 9. `ai-error.ts`: `classifyAIProviderError` e `fetchAIWithRetry` aplicados em todas as Edge Functions, retry desabilitado após o primeiro tool call

**Status: NÃO LOCALIZADO neste repositório — a arquitetura é outra, e melhor.**

`ai-error.ts`, `classifyAIProviderError` e `fetchAIWithRetry` **não existem** em
`Documents/Claude Code/marineflow-erp`. Existem em `Documents/marineflow-staging`
(`supabase/functions/_shared/ai-error.ts` + `src/tests/ai-error.test.ts`) — a cópia obsoleta, da era
Z-API/Lovable.

No repositório canônico o papel foi absorvido por um **retry centralizado dentro de `callClaude`**
(`_shared/ai/anthropic.ts:134-215`), que é o único ponto de chamada da API:
- 3 tentativas; backoff respeitando `retry-after`;
- 429/502/503 → repete; 400/401 → loga o corpo e não repete (bug de payload/credencial); 402 → créditos.

Sobre "o retry permanece desabilitado após o primeiro tool call": **a preocupação não se aplica** — o retry vive
*antes* da execução de qualquer ferramenta. Repetir a chamada re-envia o prompt ao modelo; nunca re-executa uma
tool já executada. O loop de ferramentas (`runAgentLoop`) roda por fora e não tem retry próprio; ele tem um
**orçamento de tempo** de 100 s para não estourar o teto de ~150 s da Edge Function (`agent.ts:59-62`).

→ Sem achado de retry. Consistência confirmada: todas as funções que falam com LLM passam por `callClaude`
(`ai-agent`, `finance-review`, `agenda-voice-capture`, `inbox-detector`), exceto `whatsapp-read-media`, que faz
`fetch` direto ao OpenRouter (`:88`) para uma extração leve com Haiku — sem retry, mas também sem estado.

---

## 10. Funcionalidades das migrations "MIG-01 a MIG-08" — funcionais ponta a ponta?

**Status: a nomenclatura não existe; 7 das 8 funcionalidades estão funcionais, 1 está parcial.**

A sigla `MIG-01`..`MIG-08` **não aparece em nenhum** dos 48 `.md`, dos 243 `.sql` ou do código — e uma varredura
posterior, ampliada para `C:\Users\PC\Documents\`, `C:\Users\PC\.claude\` e `C:\Users\PC\Desktop\` inteiros
(incluindo os 15 worktrees e a cópia `marineflow-staging`), **também não encontrou nenhuma ocorrência**. As
migrations reais usam timestamp. A conclusão mais provável é que a nomenclatura veio do histórico de uma
conversa anterior, não de um documento — o que importa para a Fase 2: **não existe uma lista `MIG-*` a
consultar**; a fonte da verdade são os 243 arquivos com timestamp.

Verifiquei as oito funcionalidades nomeadas (migration → código → montado em tela alcançável):

| # | Funcionalidade | Status |
|---|---|---|
| 1 | Baixa de estoque | ✅ funcional (dois modos, flag `stock_model_v2`) |
| 2 | Alerta de estoque baixo | ✅ funcional (`StockAlertDialog` montado em `ServiceOrderForm.tsx:2233`) |
| 3 | Controle de garantia | ✅ funcional (`warranty_months` no formulário) |
| 4 | Timer de serviço | ✅ funcional (`ServiceTimer` em `services-section.tsx`) |
| 5 | Fotos de progresso da OS | ✅ funcional (`ServiceOrderPhotos` em `general-sections.tsx:354`) |
| 6 | Export CSV | ✅ funcional (`src/lib/export.ts`, `export-utils.ts`) |
| 7 | **Gráfico de fluxo de caixa** | ⚠️ **parcial** — a V2 tem gráfico próprio 3/6/12m, mas o painel de programação semanal com alerta de semana negativa e detecção de duplicatas (`CashForecastPanel`) ficou só na tela legada → **[MF-AUD-050]** |
| 8 | Web Push | ✅ presente ponta a ponta (VAPID + `send-push-notification` + disparo em `ServiceOrderForm.tsx:837,903`) |

Tabela detalhada em `audit/21-banco-de-dados.md` §21.2.

---

## Resumo

| Hipótese | Status |
|---|---|
| 1 — `scheduled_start_at` no PDF | Corrigido (com pergunta em aberto) |
| 2 — Termos não renderizam | Causa real identificada (preferência global) — **P1** |
| 3 — Overflow/paginação nas listas | Corrigido |
| 4 — Dropdown de OS na Agenda | **Ainda presente — P1** |
| 5 — Grid da Agenda no mobile | Corrigido |
| 6 — UUID ao vincular técnico | Corrigido (outro defeito encontrado no trecho) |
| 7 — Itens do "Prompt #23" | 7 de 8 corrigidos; `STATUS_LABELS` pendente |
| 8 — Modelo de AI | Invertido: código certo, documento obsoleto |
| 9 — `ai-error.ts` / retry | Não localizado; arquitetura substituta é melhor |
| 10 — "MIG-01..08" | 7 funcionais, 1 parcial; nomenclatura inexistente |
