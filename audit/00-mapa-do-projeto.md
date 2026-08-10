# 00 — Mapa do Projeto (Etapa 0)

**Auditoria técnica MarineFlow ERP — Fase 1 (READ-ONLY)**
Data: 08/08/2026
Repositório auditado: `C:\Users\PC\Documents\Claude Code\marineflow-erp`
Branch: `main` — HEAD `14e3fd2` ("merge: cabecalho sticky, autosave e alvos de toque na tela de OS", 08/08/2026)

---

## 0.1 Escolha do repositório (importante)

Existem **múltiplas cópias** do MarineFlow em disco. A auditoria foi feita sobre a cópia canônica.
Evidência da comparação:

| Pasta | Branch | Último commit | `src/` | migrations | edge fns |
|---|---|---|---|---|---|
| `Documents/Claude Code/marineflow-erp` **(AUDITADA)** | `main` | `14e3fd2` — 08/08/2026 | 470 | 243 | 37 |
| `Documents/marineflow-staging` | `fix/schema-column-sync` | `59d140b` — 20/06/2026 | 293 | 101 | 27 |
| `.config/superpowers/worktrees/marineflow-erp` | detached `HEAD` | — | 0 (vazio) | 0 | 0 |

Além dessas, existem ~15 worktrees irmãos (`marineflow-erp--agenda`, `--ai`, `--compras`, `--email`, `--fases`,
`--fotos`, `--prompt`, `--tokens`, `--ui-v2`, `--viewport`, `--vinculo-os`, `-ai-operator`, `-ui-phase-1`, etc.)
em `Documents/Claude Code/`. **Não foram auditados** — são branches de trabalho que mergeiam na `main`.

> ⚠️ **Divergência já detectada entre o briefing da auditoria e o repositório real** (vira achado de categoria B
> na Etapa 3): o briefing descreve "integração WhatsApp via Z-API" e "migrations MIG-01 a MIG-08". No repositório
> canônico o WhatsApp roda em **Evolution API** (o Z-API sobrevive como segunda implementação da camada trocável
> — ver módulo 17, não é resíduo morto) e **não existe nenhuma referência à nomenclatura `MIG-01`..`MIG-08`** —
> nem no repositório, nem em `Documents/`, `.claude/` ou `Desktop/` (varredura completa, incluindo os 15
> worktrees e a cópia `marineflow-staging`). A série de migrations reais tem 243 arquivos com timestamps
> `2026MMDD`.

---

## 0.2 Estado da árvore de trabalho no início da auditoria

```
$ git status --short
?? tsconfig.node.tsbuildinfo
```

Árvore limpa exceto por um artefato de build não versionado (pré-existente, **não** criado por esta auditoria).

---

## 0.3 Stack real (verificada em `package.json`)

- **Front:** React 18.3 + TypeScript 5.8 + Vite 5.4 (`@vitejs/plugin-react-swc`)
- **UI:** shadcn/ui sobre Radix + Tailwind 3.4 + `framer-motion` 11 + `lucide-react`
- **Dados:** `@supabase/supabase-js` 2.102 + TanStack Query 5.83
- **Formulários/validação:** `react-hook-form` 7.61 + `zod` 3.25 + `@hookform/resolvers`
- **PDF:** `html2pdf.js` 0.10.2 (pin exato)
- **Testes:** Vitest 3.2 + Testing Library + jsdom **20.0.3** (versão antiga — ver nota) + Playwright 1.57
- **Resíduo Lovable:** `lovable-tagger` 1.1.13 em devDependencies, pasta `.lovable/`
- **Sem script `typecheck`** no `package.json` (só `dev`, `build`, `build:dev`, `lint`, `preview`, `test`, `test:watch`)

---

## 0.4 Volumetria por área

| Área | Arquivos | Linhas |
|---|---:|---:|
| `src/components` | 205 | 40.270 |
| `supabase/functions` | 146 | 31.503 |
| `src/pages` | 58 | 24.823 |
| `supabase/migrations` | 243 | 19.420 |
| `src/hooks` | 75 | 14.520 |
| `src/integrations` | 3 | 10.563 |
| `src/lib` | 61 | 9.312 |
| `src/v2` | 32 | 8.102 |
| `src/test` | 26 | 4.987 |
| `plans` | 17 | 4.422 |
| `src/i18n` | 4 | 1.892 |
| `docs` | 3 | 458 |
| `reports` | 40 | 272 |
| `src/types` | 1 | 215 |
| `scripts` | 13 | 81 |

**Total TS/TSX auditável (src + supabase/functions): ~146.500 linhas.**

### Maiores arquivos (candidatos naturais a dívida de manutenção)

```
10523  src/integrations/supabase/types.ts      (gerado)
 3505  src/pages/FiscalEmission.tsx
 2584  src/components/ServiceOrderForm.tsx
 1776  src/pages/SettingsPage.tsx
 1699  src/components/BankReconciliation.tsx
 1404  src/pages/AgendaPage.tsx
 1396  src/lib/pdf-generator.ts
 1332  supabase/functions/finance-review/index.ts
 1184  src/pages/ImportFiscalXML.tsx
 1122  src/components/FinanceReviewInbox.tsx
 1086  supabase/functions/fiscal-emit/index.ts
  999  supabase/functions/_shared/ai/tools/service-orders.ts
  947  src/components/service-order/form-parts.tsx
  907  src/i18n/en.ts
  894  src/pages/FinancialPage.tsx
```

---

## 0.5 Arquitetura de rotas: convivência **legado × V2**

Descoberta estrutural mais importante do mapeamento, e que condiciona toda a auditoria:
o app mantém **duas UIs completas em paralelo**, arbitradas em runtime por um componente `LegadoOuV2`
(`src/App.tsx:171-240`).

```tsx
// src/App.tsx:220
<Route path="/clients" element={<ProtectedRoute ...><LegadoOuV2 to="/v2/clients" legacy={<ClientList />} /></ProtectedRoute>} />
```

Ou seja: para ~25 telas existe uma versão legada (`src/pages/*.tsx`) e uma versão V2 (`src/v2/pages/*V2.tsx`),
e a rota `/x` redireciona para `/v2/x` **ou** renderiza a legada dependendo de configuração.

> **Precisão obtida no módulo 10 (leia junto):** nem toda rota V2 é uma reescrita. `src/v2/pages/wrapped.tsx:31-49`
> define `wrap(Comp) => <V2Shell><Comp/></V2Shell>` e aplica isso a OS, Fiscal, Settings, Agenda, WhatsApp e
> orçamento externo — nesses casos a V2 é apenas uma **casca de tema** sobre a página legada, e não existe
> duplicação de lógica. A reescrita real está nas **listas** (`OrdersListV2`, `ClientsListV2`, `VesselsListV2`,
> `MarinasListV2`, `ProductsListV2`, `ServicesListV2`, `SuppliersListV2`, `InventoryV2`, `FinancialV2`,
> `ReceivablesV2`, `CollectionsV2`, `CommissionsV2`, `CRMKanbanV2`, `DashboardV2`, `ReportsV2`,
> `PurchaseOrdersV2`, `SmartPurchaseV2`, `AuditLogV2`, `ClientDetailV2`). O risco de divergência está aí.

Consequências para a auditoria:

1. Um bug relatado pelo usuário pode existir em **uma** das duas versões apenas — cada hipótese do briefing
   precisa ser verificada nas duas.
2. Código "morto" aparente pode ser a versão legada ainda alcançável pelo fallback (**não é morto**).
3. Divergência de comportamento entre legado e V2 é achado de categoria H por definição.

Rotas públicas (fora do `ProtectedRoute`): `/login`, `/portal`, `/reset-password`, `/view/:token`,
`/design-preview`. Estas concentram o risco de RLS/exposição — auditadas no módulo 20 (Auth+RLS).

---

## 0.6 Módulos/domínios identificados

| # | Módulo | Superfície principal | Arquivos aprox. |
|---|---|---|---|
| 1 | **OS + Orçamentos** (núcleo) | `ServiceOrderForm.tsx` (2.584 l), `ServiceOrderDetail.tsx`, `ServiceOrderList.tsx`, `QuoteList.tsx`, `src/components/service-order/*` (10), `src/components/service-orders/*` (12), `OrdersListV2.tsx`, hooks `use-service-order*` (6) | ~45 |
| 2 | **PDFs** | `src/lib/pdf-generator.ts` (1.396 l), `pdf-print.ts`, `pdf-canvas-scale`, `pdf-survey`, `danfe-espelho.ts`, `PDFOptionsDialog.tsx`, `use-pdf.ts` | ~12 |
| 3 | **Financeiro + Cobranças + WhatsApp** | `FinancialPage.tsx`, `FinancialV2.tsx`, `CollectionsPage.tsx`, `src/components/collections/*` (8), `BankReconciliation.tsx` (1.699 l), `FinanceReviewInbox.tsx`, `DREPanel`, `FechamentoPanel`, 12 edge fns `whatsapp-*` | ~60 |
| 4 | **Estoque / Compras / Fiscal** | `InventoryPage`, `SmartPurchasePage`, `PurchaseOrdersPage`, `PurchasingHubPage`, `QuoteRequests*`, `ImportFiscalXML.tsx`, `FiscalEmission.tsx` (3.505 l), fns `fiscal-*`, `process-nfe-xml` | ~40 |
| 5 | **Clientes / Embarcações / Marinas / Produtos / Serviços / Fornecedores** | `ClientList/Detail`, `VesselList/Detail`, `MarinaList`, `ProductList`, `ServiceList`, `SupplierList` + pares V2 + dialogs de formulário | ~35 |
| 6 | **Agenda** | `AgendaPage.tsx` (1.404 l), `DayBoardPage.tsx`, `src/components/agenda/*` (13), `use-agenda.ts`, fns `task-automations`, `agenda-inbox-detector`, `agenda-voice-capture` | ~20 |
| 7 | **Settings / app_settings** | `SettingsPage.tsx` (1.776 l), `SettingsV2`, `use-app-settings.ts`, `MasterDataManagement.tsx`, `WhatsAppSettings.tsx` | ~12 |
| 8 | **Edge Functions** | 37 funções em `supabase/functions/` + `_shared/` (146 arquivos no total) | 146 |
| 9 | **Agente AI** | `supabase/functions/_shared/ai/**` (tools, prompts, retry), `ai-agent`, `ai-business-monitor`, `ai-daily-briefing`, `ai-whatsapp-followups`, `src/components/ai/*` (6), `use-ai-agent.ts`, `ai-context.ts` | ~40 |
| 10 | **Auth + RLS** | `use-auth.tsx`, `ProtectedRoute.tsx`, `LoginPage`, `ResetPasswordPage`, políticas nas 243 migrations, ~120 tabelas | — |
| 11 | **i18n** | `src/i18n/{index,context,pt-BR,en}.ts` (1.892 l) + consumo em toda a UI | 4 + uso |
| 12 | **Hooks e utilitários** | 75 hooks + 61 libs | 136 |

---

## 0.7 Superfície de banco de dados

Extraída de `src/integrations/supabase/types.ts` (arquivo gerado, 10.523 linhas):

- **~120 tabelas.** Blocos principais:
  - Núcleo operacional: `service_orders`, `service_order_{parts,services,expenses,photos,signatures,steps,technicians}`, `service_{cases,surveys,survey_answers,survey_templates,systems,verbs,step_blocks,step_templates}`, `time_entries`, `work_stop_reasons`
  - Cadastros: `clients`, `vessels`, `vessel_contacts`, `marinas`, `products`, `product_{aliases,categories,components,price_history,suppliers}`, `services`, `suppliers`, `payees`
  - Financeiro: `receivables`, `payables`, `payments`, `invoices`, `collections`, `collection_{contacts,templates}`, `commissions`, `financial_categories`, `cost_centers`, `periodos_fechados`, `card_installment_fees`, `exchange_rates`
  - Bancário/conciliação: `bank_{connections,transactions,charges,balance_checks}`, `reconciliation_{log,memory}`, `finance_{review_queue,rules}`, `pluggy_amostra_payload`
  - Fiscal: `fiscal_{notes,note_items,emission_drafts,document_sequences}`, `issued_fiscal_documents`, `company_fiscal_settings`, `import_sessions`
  - Compras: `purchase_orders`, `purchase_order_items`, `quote_{requests,request_items,request_sends,responses}`, `supplier_product_mappings`, `price_update_suggestions`
  - WhatsApp: `whatsapp_{messages,leads,templates,send_queue,scheduled_sends,status_scheduled,read_state,quick_replies,blocked_numbers,conversation_assignments}`, `client_whatsapp_settings`
  - Agenda: `agenda_{tasks,suggestions,detector_exclusions}`, `task_reminders`, `maintenance_plans`
  - **IA (23 tabelas!):** `ai_agent_{memory,tasks}`, `ai_business_alerts`, `ai_comms_log`, `ai_correction_patterns`, `ai_daily_briefings`, `ai_inbound_sessions`, `ai_learned_routines`, `ai_lifecycle_events`, `ai_message_feedback`, `ai_operator_{alerts_log,audit,channel_events,draft_items,drafts,memory_notes,messages,pending_actions,sessions}`, `ai_suggestion_reviews`, `ai_workflows`
  - Infra: `app_settings`, `app_users`, `app_notifications`, `app_error_logs`, `audit_log`, `saved_filters`, `push_subscriptions`, `api_references`
- **~10 views:** `v_estoque_entradas_pendentes`, `v_estoque_variancia`, `v_service_order_labor_variance`, `v_service_order_margin`, `v_service_systems_status`, `v_service_verbs_status`, `vw_os_profitability`, `erp_open_loop_facts`, `product_availability`, `unidentified_contacts`
- **~90 funções/RPCs**, incluindo `recalc_so_totals`, `register_deposit_and_convert`, `register_payment_and_update_balance`, `receive_po`, `confirm_nfe_import`/`preview_nfe_import`/`revert_nfe_import`, `settle_nfe_stock_and_receivable`, `compute_purchase_needs`, `is_admin`/`is_admin_or_financial`/`is_external_seller`

> Nota de método: a Etapa 2 (módulo 21 — Banco) confronta este schema **gerado** com as 243 migrations e com o
> uso real no código. Nenhuma consulta de escrita será executada; leitura via schema em disco.

---

## 0.8 Cobertura de teste — visão de superfície

**71 arquivos de teste.** Distribuição:

- `src/lib/*.test.ts` — 17 (lógica pura: pdf, quote-deposit, os-financials, route-sheet, purchase-needs, …)
- `src/test/*.test.ts` — 24 (banking, fiscal, nfe, dre, …)
- `*.smoke.test.tsx` — 18 (render de tela; padrão adotado após incidente de TDZ)
- `src/hooks/*.test.ts` — 4
- `supabase/functions/**/*.test.ts` — **1** (`_shared/ai/product-fiscal.test.ts`)

> Assimetria já visível: **31.503 linhas de Edge Function cobertas por 1 arquivo de teste.** Detalhado no
> módulo 18 e no módulo 22 (Testes).

---

## 0.9 Documentação encontrada (detalhada na Etapa 1)

48 arquivos `.md` no repositório, fora `node_modules`/`.git`, distribuídos em: raiz (`CLAUDE.md`, `README.md`),
`docs/` (3), `plans/` (17), `.claude/`, `.github/`, `reports/` (40 arquivos, 272 linhas — em maioria saídas curtas
de execução, não documentação). Inventário completo em `audit/01-inventario-docs.md`.

---

## 0.10 Ordem de auditoria adotada

Ajustada em relação ao briefing para refletir o mapa real (o projeto tem módulos que o briefing não previa —
Fiscal, Compras, Bancário, CRM, Portal do Cliente, Vendedor Externo):

| Arquivo | Módulo |
|---|---|
| `10-os-orcamentos.md` | OS + Orçamentos |
| `11-pdfs.md` | Geração de PDFs |
| `12-financeiro-cobrancas.md` | Financeiro, Cobranças, Bancário |
| `13-estoque-compras-fiscal.md` | Estoque, Compras, Fiscal |
| `14-cadastros.md` | Clientes/Embarcações/Marinas/Produtos/Serviços/Fornecedores |
| `15-agenda.md` | Agenda + Day Board + automações |
| `16-settings.md` | Settings / app_settings |
| `17-whatsapp.md` | Integração WhatsApp (Evolution) |
| `18-edge-functions.md` | 37 Edge Functions + `_shared` |
| `19-agente-ai.md` | Agente AI (tools, prompts, retry, orquestração) |
| `20-auth-rls.md` | Auth + RLS |
| `21-banco-de-dados.md` | Migrations × schema × uso |
| `22-i18n.md` | i18n |
| `23-hooks-utils.md` | Hooks e utilitários compartilhados |
| `90-docs-vs-codigo.md` | Cross-check documentação × código |
| `95-hipoteses-conhecidas.md` | Status das 10 hipóteses do briefing |
| `99-sumario-executivo.md` | Sumário, ondas, decisões |

---

*Etapa 0 concluída. Nenhum arquivo fora de `audit/` foi criado, alterado ou removido.*
