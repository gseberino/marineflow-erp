# Blueprint de Integração — Laudos, Propostas e IA no MarineFlow ERP

> **Status:** Análise técnica / blueprint. Nenhum código de produção, migration, Edge Function ou prompt foi adicionado ao projeto. Este documento é a base para decisões de arquitetura e priorização das próximas fases.
>
> **Branch:** `analysis/report-ai-integration-blueprint` (criada a partir de `staging/marineflow-functional`).
>
> **Data:** 2026-05-19

---

## 0. Sumário Executivo

O usuário tem 5 repositórios antigos e quer **incorporar capacidades selecionadas no MarineFlow ERP**, sem criar sistemas paralelos. A análise mostra:

| Repositório | Veredito global |
|---|---|
| **Gerador-de-Relatorios** | Alto valor — checklists náuticos, prompts multimodais (foto+áudio), estrutura técnico+executivo, queda de tensão. Reaproveitar **código + conceito**, descartar Firebase/Gemini-no-client. |
| **sailahead-ai** | Alto valor para histórico de IA — schema `ai_conversations` / `ai_messages` / `user_settings` / `activity_logs`, padrão de Edge Function streaming. Descartar marketing/SEO. |
| **seawise-manager** | Valor médio (esqueleto). Maior parte é `PlaceholderPage`. Conceitos úteis: `maintenance_logs`, `cleaning_routines`, `tasks` (Kanban). MarineFlow **já cobre** boats/clientes/inventário. |
| **nautiads-deep-dive** | **Baixo valor técnico** — boilerplate Lovable, README placeholder, zero lógica de negócio. |
| **my-business-snapshot** | **Baixo valor técnico** — idem nautiads-deep-dive; mesmo template, sem implementação real. |

**Recomendação de primeira implementação (Fase 1):** Aba **"Laudos / Inspeção"** dentro de `ServiceOrderDetail.tsx` em modo **read-only / dados mockados**, sem migration, reaproveitando o checklist náutico e a estrutura técnico+executivo do Gerador-de-Relatorios — somente UI, para validar fluxo antes de tocar em schema/Edge Functions.

---

## 1. Estado Atual do MarineFlow

Confirmado via inspeção direta da branch `staging/marineflow-functional`:

| Domínio | Como está hoje |
|---|---|
| **Tela de OS** | `src/pages/ServiceOrderDetail.tsx` com `<Tabs>` (`details`, `timeline`). Form em `src/components/ServiceOrderForm.tsx`. |
| **Fotos** | `src/components/ServiceOrderPhotos.tsx` → bucket Supabase `service-order-photos`, tabela `service_order_photos` (photo_type: before/progress/after/problem). |
| **Assinaturas** | `src/components/SignaturePad.tsx` (canvas → PNG base64). Edge Function `supabase/functions/submit-signature` → bucket `signatures`, tabela `service_order_signatures` (hash, IP, user-agent, snapshot de termos, superseded_at). |
| **PDF** | Client-side via `src/lib/pdf-generator.ts` + `src/hooks/use-pdf.ts`. `PDFOptions` configura flags (preços, desconto, imposto, comissão, termos, assinatura, imagens). |
| **Portal público** | `src/pages/PublicServiceOrderView.tsx` em `/view/:token` via `share_token` da OS; cliente pode assinar. |
| **IA atual** | Edge Function `supabase/functions/ai-agent/index.ts` → Gemini (`gemini-3-flash`) via endpoint OpenAI-compat. Tools READ (15): `search_clients`, `search_vessels`, `search_products`, `list_agenda`, `list_service_orders`, `get_service_order`, `get_client_history`, `list_pending_collections`, `search_services`, `list_technicians`, `list_marinas`, `get_vessel_history`, `get_financial_dre`, `get_technician_commissions`, `get_os_profitability`. Tools WRITE (6): `create_service_order`, `update_service_order`, `create_client`, `send_whatsapp`, `adjust_inventory`, `propose_action` (todas atrás de confirmação). Frontend: `src/hooks/use-ai-agent.ts` via `supabase.functions.invoke('ai-agent', …)`. **Histórico em memória React apenas — não há tabela `ai_*` persistida.** Sem rate limit visível. |
| **Audit log** | Tabela `audit_log`. `src/hooks/use-audit-log.ts` (`writeAuditLog`, `useAuditLog`, `useRecordHistory`). Página `src/pages/AuditLogPage.tsx`. |
| **Roles** | `app_users.role`: `admin`, `technician`, `financial`, `seller`, `external_seller`, `other`. `ProtectedRoute` em `App.tsx` recebe `roles[]` + `groupId`. |
| **Dashboard atual** | `src/pages/Dashboard.tsx` + `src/hooks/use-dashboard.ts` — Receivables/Payables, pagamentos do mês, OS abertas, distribuição de status, receita 5 meses (Recharts), produtos com estoque baixo. **Falta:** lucratividade por cliente, margem, taxa de conversão de orçamentos, fluxo de caixa previsto, KPIs de equipe. |
| **WhatsApp** | Tabelas `whatsapp_leads`, `whatsapp_messages`, `whatsapp_scheduled_sends`, `client_whatsapp_settings`. Edge Functions `whatsapp-*` e `zapi-*`. |
| **Padrão de hooks** | @tanstack/react-query com `useQuery`/`useMutation`, supabase via `src/integrations/supabase/client`. |

**Validação inicial (este branch):**

- `git status --short`: limpo (apenas `.gitignore M` preexistente).
- `git branch --show-current`: `analysis/report-ai-integration-blueprint`.
- `npm run build`: **OK** (warning de chunk grande, preexistente).
- `npm test`: **OK** — 8 arquivos, 26 testes, 100% passando.

---

## 2. ENTREGÁVEL 1 — Matriz de Reaproveitamento

| Repo | Funcionalidade | Arquivos relevantes | Valor p/ MarineFlow | Reaproveitar como | Dependências | Risco técnico | Risco produto | Esforço | Prioridade |
|---|---|---|---|---|---|---|---|---|---|
| Gerador-de-Relatorios | Checklist náutico (17 itens, grupos ABYC) | `App.tsx` `MARINE_CHECKLIST`, `components/TechnicalChecklist.tsx` | Alto | **Código** (porta dados; UI re-escrever) | Nenhuma | Baixo | Baixo | M | **P1** |
| Gerador-de-Relatorios | Checklist motorhome/RV (16 itens) | `App.tsx` `RV_CHECKLIST` | Médio | **Conceito** (manter como segundo template opcional) | Nenhuma | Baixo | Baixo | S | P3 |
| Gerador-de-Relatorios | Prompt de laudo técnico + executivo (JSON estruturado, status green/yellow/red) | `lib/geminiService.ts` `generateMarineReport` | Alto | **Conceito** (rewrite no Edge Function, versionado) | Gemini via Edge | Baixo | Médio (variação de saída) | M | **P1** |
| Gerador-de-Relatorios | Análise multimodal (imagens+áudio numa só call Gemini) | `lib/geminiService.ts` `analyzeImagesWithAI`, `lib/videoUtils.ts` | Alto | **Código** (videoUtils porta direto; orquestração no Edge) | Gemini multimodal | Médio (custo, latência) | Médio | M | P2 |
| Gerador-de-Relatorios | Enhance notes / polimento de texto técnico | `lib/geminiService.ts` `enhanceNotesWithAI` | Médio | **Conceito** (Edge Function pequena) | Gemini | Baixo | Baixo | S | P2 |
| Gerador-de-Relatorios | Transcrição de áudio → notas | `lib/geminiService.ts` `transcribeAudio` | Médio | **Conceito** (Edge Function) | Gemini multimodal | Médio | Baixo | S | P3 |
| Gerador-de-Relatorios | Estrutura ReportView (técnico + executivo + evidências) | `components/ReportView.tsx` | Alto | **Código** (porta layout, descarta Firebase) | react-markdown | Baixo | Baixo | M | **P1** |
| Gerador-de-Relatorios | Cálculo queda de tensão `V_drop = (2·L·I·0.017)/A` + limites ABYC (3%/10%) | `lib/utils.ts` `calculateVoltageDrop`, `components/VoltageDropCalculator.tsx` | Médio | **Código** (utilitário + componente) | Nenhuma | Baixo | Baixo | S | P2 |
| Gerador-de-Relatorios | HistoryView (lista Firestore) | `lib/db.ts`, `components/HistoryView.tsx` | Baixo (já temos padrão) | **Descartar código**, manter conceito de versão | n/a | Baixo | Baixo | n/a | n/a |
| Gerador-de-Relatorios | Extração de frames de vídeo + WAV manual | `lib/videoUtils.ts` | Médio | **Código** (utilitário client-side) | Web APIs | Baixo | Baixo | S | P3 |
| Gerador-de-Relatorios | PDF via `window.print()` + CSS `@media print` | `components/ReportView.tsx` | Baixo (MarineFlow já tem `pdf-generator.ts`) | **Descartar** — usar pipeline existente | n/a | n/a | n/a | n/a | n/a |
| sailahead-ai | Schema `ai_conversations` / `ai_messages` | `supabase/migrations/*.sql` | Alto | **Código** (migration adaptada, mesmo padrão) | Supabase | Baixo | Baixo | S | **P1** |
| sailahead-ai | Edge Function chat com SSE streaming + injeção de `user_settings` | `supabase/functions/ai-chat/index.ts` | Alto | **Código** (rewrite p/ Gemini direto, sem Lovable Gateway) | Gemini, Supabase Edge | Médio (streaming Deno) | Baixo | M | P2 |
| sailahead-ai | `user_settings` (business_name, tone, main_goal, region…) | migration | Médio | **Conceito** (estender p/ contexto do estaleiro/operacional) | Supabase | Baixo | Baixo | S | P2 |
| sailahead-ai | `activity_logs` + função `log_activity` | migration + `DashboardActivity.tsx` | Médio | **Conceito** — MarineFlow já tem `audit_log` mais rico (table_name/record_id) | Supabase | Baixo | Baixo | n/a | mantém audit_log |
| sailahead-ai | `useDashboardData` (paralelizar counts via Promise.all) | `hooks/useDashboardData.ts` | Médio | **Conceito** (padrão de agregação para dashboard executivo) | React Query | Baixo | Baixo | S | P2 |
| sailahead-ai | Onboarding (5 steps, framer-motion) | `pages/Onboarding.tsx` | Baixo | **Conceito** (não urgente) | framer-motion | Baixo | Baixo | M | P3 |
| sailahead-ai | Marketing / SEO / posts / campaigns / appointments | múltiplos | Nenhum | **Descartar** | n/a | n/a | n/a | n/a | n/a |
| seawise-manager | `maintenance_logs` (next_due_date, intervals) | migration | Médio | **Conceito** (não confundir com OS — é plano de manutenção preventiva) | Supabase | Baixo | Médio (sobreposição) | M | P3 |
| seawise-manager | `cleaning_routines` (frequency enum) | migration | Baixo | **Conceito** | Supabase | Baixo | Baixo | M | P4 |
| seawise-manager | `tasks` Kanban-ready (status enum) | migration | Médio | **Conceito** — MarineFlow tem `agenda_tasks`; avaliar se vale Kanban | Supabase | Baixo | Baixo | M | P3 |
| seawise-manager | CRM leads + clients split | migration | Baixo | **Descartar** — MarineFlow já tem CRM Kanban (`CRMKanbanPage`) | n/a | n/a | n/a | n/a | n/a |
| seawise-manager | Boats CRUD + Zod | `pages/Boats.tsx`, `lib/validations.ts` | Baixo | **Descartar** — duplicaria `VesselFormDialog` | n/a | n/a | n/a | n/a | n/a |
| seawise-manager | Inventory (`products`) | migration | Baixo | **Descartar** — MarineFlow tem `InventoryPage` | n/a | n/a | n/a | n/a | n/a |
| nautiads-deep-dive | Boilerplate Lovable, 1 commit, README placeholder | toda raiz | Nenhum | **Descartar** — baixo valor técnico, sem código de negócio | n/a | n/a | n/a | n/a | n/a |
| my-business-snapshot | Boilerplate Lovable idêntico ao acima | toda raiz | Nenhum | **Descartar** — baixo valor técnico (commit "Migrate to real user dashboard" não foi entregue) | n/a | n/a | n/a | n/a | n/a |

---

## 3. ENTREGÁVEL 2 — Arquitetura Proposta

> Princípios firmes: (i) tudo dentro do MarineFlow; (ii) **rascunho com aprovação humana** antes de salvar como definitivo, enviar ao cliente ou faturar; (iii) **Gemini só via Supabase Edge Function** (chave em `GEMINI_API_KEY` secret); (iv) reaproveitar PDF, fotos, assinatura, audit log já existentes; (v) RLS sempre; (vi) prompts versionados em código (não no DB).

### 3.1 Módulo 1 — Laudos Técnicos / Inspeção dentro da OS

**Onde mora:** nova aba `inspection` em `ServiceOrderDetail.tsx`, ao lado de `details` e `timeline`.

**Componentes React sugeridos** (todos sob `src/components/inspection/`):

- `InspectionTab.tsx` — orquestrador da aba (carrega templates, lista laudos, gating de permissão).
- `InspectionTemplatePicker.tsx` — combobox de `inspection_templates` (Náutico / RV / customizado).
- `ChecklistRunner.tsx` — render dos itens agrupados por categoria; status `pending|ok|warning|fail`; textarea de observações; ícone de "enriquecer com IA" (chama Edge).
- `InspectionEvidenceGrid.tsx` — reutiliza fotos da OS via `useServiceOrderPhotos`; permite anexar evidências novas só se status ≠ finalizada.
- `InspectionSignatureBlock.tsx` — primeiro tenta reaproveitar `service_order_signatures` ativa; se não houver, abre `SignaturePad`.
- `InspectionReportDraft.tsx` — exibe rascunho `technical` + `executive` lado a lado (read-only inicialmente) + status global verde/amarelo/vermelho.
- `InspectionPDFPreview.tsx` — botão "Gerar PDF" que injeta o relatório em `pdf-generator.ts` com novo `PDFOptions.includeInspectionReport`.

**Hooks sugeridos** (`src/hooks/`):

- `use-inspection-templates.ts` — `useQuery` em `inspection_templates` + `inspection_template_items`.
- `use-inspections.ts` — CRUD em `service_order_inspections` (lista por OS, criar rascunho, atualizar, finalizar).
- `use-inspection-ai-draft.ts` — `useMutation` que invoca Edge `inspection-ai-draft` e retorna `{ technical, executive, status }` sem persistir até confirmação.
- `use-inspection-pdf.ts` — wrapper sobre `use-pdf` com flag `inspectionMode`.

**Edge Functions sugeridas** (`supabase/functions/`):

- `inspection-ai-draft/` — recebe `{ inspection_id }`, busca contexto (OS, cliente, embarcação, checklist preenchido, fotos URLs, observações), chama Gemini multimodal com prompt versionado (`v1`), retorna JSON `{ technical_md, executive_md, status_global, prompt_version }`. **Não persiste** — frontend grava após review.
- `inspection-ai-enrich-item/` — porta de `processChecklistItemAI` (pega `inspection_item_id`, retorna `{ enhanced_text, follow_up_questions[] }`).
- `inspection-ai-transcribe/` — porta de `transcribeAudio` (recebe URL Supabase Storage, retorna texto).

Reaproveita-se a infra do `ai-agent` (mesmo `client.ts`, mesmo padrão `Deno.env.get('GEMINI_API_KEY')`, mesmo `corsHeaders`).

**Fluxo de aprovação humana:**

```
ChecklistRunner → "Gerar rascunho com IA" → Edge inspection-ai-draft
  → InspectionReportDraft (read-only)
  → Técnico edita (technical_md_edited) → "Salvar rascunho" → status = 'draft'
  → "Marcar como revisado" → status = 'reviewed'
  → "Gerar PDF" (somente após reviewed)
  → "Enviar ao cliente" (FASE FUTURA — não na Fase 1; sempre com diálogo de confirmação)
```

**Logs/auditoria:** cada transição de status do `service_order_inspections` chama `writeAuditLog` com `table_name='service_order_inspections'`, `action='status_change'`, `previous_value`, `new_value`, `reason` (opcional).

**Permissões:**

- `admin`, `technician`: criar/editar laudo.
- `seller`, `financial`: somente leitura.
- `external_seller`: sem acesso.
- `other`: configurável via `visible_areas` em `app_users.metadata`.

**Fallback IA:** se Edge retornar erro/timeout, frontend mostra "Não foi possível gerar rascunho com IA — preencher manualmente" e mantém o formulário editável. O laudo continua válido sem IA.

**Limites para evitar custo e abuso:**

- Rate limit no Edge: `max 10 inspection-ai-draft` por OS por dia (tabela `ai_rate_limits` simples por `user_id`+`function_name`+`scope_id`).
- Timeout de 90s por chamada.
- Compressão de imagens client-side antes de enviar URLs para o Edge (já temos `compress-image.ts`? checar; senão usar `browser-image-compression`).

**Versionamento de prompt:** constantes em `supabase/functions/_shared/prompts/inspection_v1.ts`. Cada chamada loga `prompt_version` no `ai_generations`. Nova versão = novo arquivo, sem `if/else` no código.

### 3.2 Módulo 2 — Gerador de Propostas / Orçamentos com IA

> Já existe `external_quotes` (página `ExternalQuoteNewPage`, etc.). A proposta com IA é uma **camada de assistência**, não um sistema novo.

**Componentes:**

- `ProposalAIPanel.tsx` em `ExternalQuoteNewPage` — sidebar que oferece "Sugerir escopo", "Sugerir itens não inclusos", "Sugerir observações técnicas", "Gerar apresentação comercial".
- `ProposalDraftDiff.tsx` — exibe sugestão da IA vs valor atual do form com botões "Aceitar" / "Substituir" / "Descartar" por campo.

**Hook:**

- `use-proposal-ai.ts` — `useMutation` por tipo de sugestão.

**Edge Function:** `proposal-ai-draft/`

- Recebe `{ client_id, vessel_id?, service_order_id?, requested_section: 'scope'|'exclusions'|'tech_notes'|'commercial_intro' }`.
- Busca contexto: histórico do cliente (`get_client_history` reaproveita lógica do `ai-agent`), embarcação, OS de referência, serviços/produtos já selecionados, valores.
- Retorna **texto markdown** (não JSON estruturado neste primeiro momento) + `prompt_version`.

**Tabela `proposal_drafts`:** opcional na Fase B — armazenar histórico de versões geradas para auditoria.

**Aprovação humana:** mesmo padrão do Módulo 1 — rascunho mostrado, usuário aceita/rejeita por trecho antes de virar conteúdo da `external_quote`.

### 3.3 Módulo 3 — Histórico de IA e Recomendações

**Tabelas** (ver §4):

- `ai_conversations` (id, user_id, scope_type, scope_id, assistant_type, title, …)
- `ai_messages` (conversation_id, role, content, tool_calls JSONB, tokens, model, prompt_version, …)
- `ai_generations` (registro de cada output não-conversacional: rascunho de laudo, sugestão de proposta, transcrição) — útil para "histórico de IA" mesmo fora de chat.
- `ai_recommendations` (recomendações pro-ativas geradas off-band, ex: "OS XYZ está há 14 dias sem evolução").

**UI:**

- Página `AIHistoryPage.tsx` — lista de conversas + filtro por escopo (OS, cliente, embarcação).
- Aba "Recomendações" no Dashboard.
- Cada OS/cliente/embarcação tem deep-link: "Ver conversas de IA relacionadas".

**Migração suave do `use-ai-agent` atual:** o widget `AIAgentWidget` passa a persistir `messages` em `ai_messages` após cada turno (em vez de só estado React). Backward-compat: se `conversation_id` não existir, cria.

### 3.4 Módulo 4 — Dashboard Executivo

Reaproveita `Dashboard.tsx` como ponto de entrada e adiciona **modo executivo** (toggle ou rota `/dashboard/executive`).

**Novos cards (todos via React Query + RPCs no Supabase):**

- Margem média por OS (mês corrente vs anterior).
- Top 5 clientes por receita (90 dias).
- Top 5 técnicos por OS concluída.
- Taxa de conversão de `external_quotes` → `service_orders`.
- Previsão de fluxo de caixa (3 meses, somando `receivables.due_date` − `payables.due_date`).
- Alertas: clientes com ≥ 3 cobranças atrasadas, OS sem evolução há > 7 dias, estoque baixo crítico.

Padrão `useDashboardData` (paralelizar counts via `Promise.all`) é o conceito copiado do sailahead-ai.

### 3.5 Módulo 5 — Evolução futura do assistente operacional

Quando o histórico estiver persistido (Módulo 3), o `ai-agent` pode:

- Carregar últimas N mensagens da conversa para continuação.
- Receber `user_settings` (`use-app-settings`) no system prompt — tom de voz, formalidade, papel.
- Receber `scope` da conversa (OS X, cliente Y) — limita tools a esse escopo, reduzindo alucinação.
- Sugerir ações pro-ativas via cron: roda 1x/dia uma Edge `ai-proactive-scan` que gera entradas em `ai_recommendations`.

Nada disso muda os contratos das tools atuais.

---

## 4. ENTREGÁVEL 3 — Proposta de Tabelas Supabase

> **NENHUMA migration aplicada.** Esta seção descreve o schema sugerido para revisão.

Tabelas equivalentes já presentes? **Não** — verificado via `ls supabase/migrations`: não há `inspection_*`, `ai_conversations`, `ai_messages`, `proposal_drafts`. (Existem `service_order_*` e `audit_log`, que serão referenciados, não duplicados.)

### 4.1 `inspection_templates`

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `name` | text | "Náutico — Sistemas Elétricos ABYC", "Motorhome v1" |
| `domain` | text check | `'marine'`, `'rv'`, `'custom'` |
| `version` | int default 1 | |
| `is_active` | bool default true | |
| `created_by` | uuid → app_users.user_id | |
| `created_at`, `updated_at` | timestamptz | |

- **Finalidade:** catálogo de tipos de laudo.
- **RLS:** SELECT para qualquer `app_users.active=true`; INSERT/UPDATE somente `admin`.
- **Índices:** (`domain`, `is_active`).
- **Risco:** baixo. **Fase A.** Pode ser adiada se template ficar **hardcoded em código** na Fase 1 (recomendado para piloto).

### 4.2 `inspection_template_items`

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `template_id` | uuid FK → inspection_templates ON DELETE CASCADE | |
| `group_name` | text | "Banco de Baterias", "Distribuição DC"… |
| `category` | text | sub-categoria opcional |
| `item_order` | int | ordenação |
| `title` | text | enunciado do item |
| `description` | text | guia para o técnico |
| `is_critical` | bool default false | influencia status global |
| `default_normative_ref` | text | ex.: "ABYC E-11" |

- **Finalidade:** itens do checklist.
- **RLS:** mesmo de `inspection_templates`.
- **Índices:** (`template_id`, `item_order`).
- **Risco:** baixo. **Fase A** se for usar templates editáveis no DB.

### 4.3 `service_order_inspections`

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `service_order_id` | uuid FK → service_orders ON DELETE CASCADE | |
| `template_id` | uuid FK → inspection_templates | |
| `template_snapshot` | jsonb | snapshot do template no momento da criação (auditabilidade) |
| `status` | text check | `'draft'`, `'reviewed'`, `'signed'`, `'archived'` |
| `status_global` | text check | `'green'`, `'yellow'`, `'red'`, null |
| `technical_md` | text | relatório técnico (markdown) — preenchido por IA, editável |
| `executive_md` | text | relatório executivo (markdown) |
| `voltage_drop_results` | jsonb | array de cálculos opcionais |
| `prompt_version` | text | quando gerado por IA |
| `ai_generation_id` | uuid FK → ai_generations | rastreabilidade |
| `signature_id` | uuid FK → service_order_signatures | reaproveita assinatura existente |
| `created_by`, `reviewed_by` | uuid | |
| `created_at`, `reviewed_at`, `signed_at` | timestamptz | |

- **Finalidade:** o laudo em si, vinculado à OS.
- **RLS:** `service_order_id` → mesma policy de leitura/escrita de `service_orders` (já existente).
- **Índices:** (`service_order_id`), (`status`), (`created_at desc`).
- **Risco:** médio (relacionamento com 5 entidades). **Fase A.**

### 4.4 `service_order_inspection_items`

| Coluna | Tipo |
|---|---|
| `id` | uuid PK |
| `inspection_id` | uuid FK → service_order_inspections ON DELETE CASCADE |
| `template_item_id` | uuid FK → inspection_template_items |
| `status` | text check `'pending','ok','warning','fail','na'` |
| `observations` | text |
| `ai_enriched` | bool default false |
| `evidence_photo_ids` | uuid[] (FK lógico → service_order_photos.id) |
| `voltage_drop_input` | jsonb null |
| `voltage_drop_result` | jsonb null |
| `created_at`, `updated_at` | timestamptz |

- **Finalidade:** cada item respondido.
- **RLS:** via join com `service_order_inspections`.
- **Índices:** (`inspection_id`), (`status`).
- **Risco:** baixo. **Fase A.**

### 4.5 `service_order_reports` *(opcional, Fase 3)*

Versionamento de PDFs gerados (técnico vs executivo) — guarda URL Storage + hash. **Pode ser adiada** se `pdf-generator.ts` continuar gerando ad-hoc.

### 4.6 `service_order_report_media` *(opcional)*

Anexos extras de mídia (vídeos, áudios) vinculados ao laudo, separados de `service_order_photos`. **Pode ser adiada** — reaproveitar `service_order_photos` adicionando coluna `media_type` é mais simples.

### 4.7 `ai_conversations`

| Coluna | Tipo |
|---|---|
| `id` | uuid PK |
| `user_id` | uuid → auth.users |
| `assistant_type` | text check (`'ops'`, `'inspection'`, `'proposal'`, `'general'`) |
| `scope_type` | text null check (`'service_order'`, `'client'`, `'vessel'`, null) |
| `scope_id` | uuid null |
| `title` | text |
| `created_at`, `updated_at` | timestamptz |

- **Finalidade:** agrupador de mensagens.
- **RLS:** `user_id = auth.uid()`.
- **Índices:** (`user_id`, `updated_at desc`), (`scope_type`, `scope_id`).
- **Fase B.**

### 4.8 `ai_messages`

| Coluna | Tipo |
|---|---|
| `id` | uuid PK |
| `conversation_id` | uuid FK ON DELETE CASCADE |
| `role` | text check (`'user'`,`'assistant'`,`'tool'`,`'system'`) |
| `content` | text |
| `tool_calls` | jsonb null |
| `tool_results` | jsonb null |
| `model` | text |
| `prompt_version` | text |
| `tokens_in`, `tokens_out` | int |
| `created_at` | timestamptz |

- **RLS:** via join com `ai_conversations`.
- **Índices:** (`conversation_id`, `created_at`).
- **Fase B.**

### 4.9 `ai_generations`

Registros de gerações **não-conversacionais** (rascunho de laudo, proposta, transcrição). Permite UI "Histórico de IA" mesmo sem chat.

| Coluna | Tipo |
|---|---|
| `id` | uuid PK |
| `user_id` | uuid |
| `function_name` | text (`'inspection-ai-draft'`, etc.) |
| `scope_type`, `scope_id` | igual a ai_conversations |
| `input_summary` | jsonb (sem PII grande) |
| `output` | jsonb |
| `prompt_version` | text |
| `model` | text |
| `tokens_in`, `tokens_out` | int |
| `latency_ms` | int |
| `status` | text (`'ok'`,`'error'`,`'rate_limited'`) |
| `error_message` | text null |
| `created_at` | timestamptz |

- **RLS:** `user_id = auth.uid()` para read; INSERT só do service role (Edge).
- **Fase A** (mesmo no piloto, para já capturar custo).

### 4.10 `ai_recommendations` *(Fase C)*

Pro-ativas, geradas off-band.

| Coluna | Tipo |
|---|---|
| `id` | uuid PK |
| `scope_type`, `scope_id` | text/uuid |
| `kind` | text (`'os_stalled'`, `'overdue_client'`, `'maintenance_due'`…) |
| `priority` | text |
| `title`, `body_md` | text |
| `status` | text (`'open'`,`'acknowledged'`,`'dismissed'`,`'resolved'`) |
| `created_at`, `resolved_at` | timestamptz |

### 4.11 `proposal_drafts` *(Fase B, opcional)*

Versões de propostas geradas com IA antes de virarem `external_quote`. **Pode ser adiada** — guardar dentro de `external_quotes.metadata jsonb` no início.

### 4.12 `ai_rate_limits`

| `user_id`, `function_name`, `scope_id`, `window_start`, `count` |

Tabela simples para enforcement. **Fase A**.

---

## 5. ENTREGÁVEL 4 — Fluxo de UX

### 5.1 Dentro da OS — "Laudos / Inspeção"

```
ServiceOrderDetail
  └─ Tabs
     ├─ Detalhes (existente)
     ├─ Histórico (existente)
     └─ Laudos / Inspeção (NOVO)
        │
        ├─ [Lista de laudos da OS]   "Novo laudo +"
        │    ├─ Laudo #1  status: signed   técnico: João   2026-05-10
        │    └─ Laudo #2  status: draft    técnico: Você   2026-05-19
        │
        └─ [Editor de laudo]
           1. Escolher template (Náutico / RV / …)
           2. Preencher checklist por categoria
              - cada item: status, observação, ✨ "Enriquecer com IA"
              - anexar evidência (reaproveita fotos da OS)
              - Calculadora de queda de tensão como tool inline
           3. "Gerar rascunho com IA" → mostra technical_md + executive_md + status global
           4. Editar markdown manualmente se necessário
           5. "Salvar como rascunho" → status='draft'
           6. "Marcar como revisado" → status='reviewed' (gating: admin/technician)
           7. Bloco de assinatura
              - se OS já tem signature ativa: oferece reaproveitar
              - senão: SignaturePad (componente atual)
              → status='signed'
           8. "Gerar PDF" (executivo / técnico / ambos)
              - usa pdf-generator com flag includeInspectionReport
           9. Envio para cliente: **FORA da Fase 1**.
              Quando vier, sempre com modal "Você confirma envio para <cliente>?" e log em audit_log.
```

### 5.2 Dentro de Proposta / Orçamento

```
ExternalQuoteNewPage
  ├─ formulário atual (cliente, vessel, services, products, valores)
  └─ Sidebar IA (NOVO)
     ├─ "Sugerir escopo" → texto markdown
     ├─ "Sugerir itens NÃO inclusos"
     ├─ "Sugerir observações técnicas"
     ├─ "Gerar apresentação comercial"
     │
     │ Cada sugestão exibe diff vs valor atual:
     │   [Aceitar] [Substituir trecho] [Descartar]
     │
     └─ "Salvar rascunho" (não envia)
        "Gerar PDF de proposta" (usa pipeline atual)
        Envio: FORA da Fase 1.
```

---

## 6. ENTREGÁVEL 5 — Plano de Implementação em Fases

### Fase 0 — Análise (esta entrega)

- **Objetivo:** blueprint validado.
- **Arquivos:** `docs/analysis/report-ai-integration-blueprint.md`.
- **Risco:** nenhum.
- **Validação:** revisão humana.
- **Critério de aceite:** usuário aprova prioridades e veredito.
- **Rollback:** descartar o branch.

### Fase 1 — Piloto frontend isolado, **read-only / mock**

- **Objetivo:** criar aba "Laudos / Inspeção" em `ServiceOrderDetail` exibindo dados **mockados em código** (template náutico hardcoded, sem persistência), reaproveitando `<Tabs>`, `<ServiceOrderPhotos>` e `<SignaturePad>` apenas para layout. **Zero migration.** **Zero Edge Function nova.**
- **Arquivos prováveis:**
  - `src/pages/ServiceOrderDetail.tsx` (adicionar TabsTrigger e TabsContent).
  - `src/components/inspection/*` (novos componentes, todos client-side com dados de `src/lib/inspection/marine-template.ts`).
  - `src/lib/inspection/marine-template.ts` — port do `MARINE_CHECKLIST`.
  - `src/lib/inspection/voltage-drop.ts` — port de `calculateVoltageDrop`.
  - `src/lib/inspection/voltage-drop.test.ts` — adicionar testes unitários.
- **Risco:** baixo. Nada toca o backend.
- **Validação:**
  - `npm run build` passa.
  - `npm test` passa.
  - Smoke manual: abre OS existente → aba nova aparece → checklist renderiza → calculadora calcula.
- **Critérios de aceite:**
  - Não quebra `details` nem `timeline`.
  - Funciona offline / em desenvolvimento sem Gemini.
  - Roles `seller`/`external_seller` veem o necessário sem erro.
- **Rollback:** reverter commit no branch; `staging/marineflow-functional` intocada.

### Fase 2 — Persistência de laudos + IA de rascunho

- **Objetivo:** salvar rascunho de laudo. Edge `inspection-ai-draft` chamando Gemini.
- **Arquivos:**
  - Migration `supabase/migrations/<ts>_inspection_core.sql` (cria 4 tabelas: `inspection_templates`, `inspection_template_items`, `service_order_inspections`, `service_order_inspection_items`, `ai_generations`, `ai_rate_limits`).
  - `supabase/functions/inspection-ai-draft/index.ts`.
  - `supabase/functions/_shared/prompts/inspection_v1.ts`.
  - Hooks `use-inspection-templates.ts`, `use-inspections.ts`, `use-inspection-ai-draft.ts`.
- **Risco:** médio. Migration grande, RLS nova. Aplicar primeiro em ambiente de staging.
- **Validação:**
  - `npm run build` + `npm test`.
  - `migration:dry-run:staging` antes de aplicar.
  - Smoke em staging: criar 1 laudo, gerar rascunho, salvar.
- **Critérios de aceite:** rascunho gerado em ≤ 30s típico; sem PII vazado em logs; rate limit ativo.
- **Rollback:** migration reversa pronta no mesmo arquivo (`DOWN` comentado, executado manualmente).

### Fase 3 — PDF do laudo + histórico de versões

- **Objetivo:** botão "Gerar PDF" do laudo, integrado em `pdf-generator.ts`. Opcional: `service_order_reports`.
- **Arquivos:**
  - Estender `src/lib/pdf-generator.ts` com seções `Inspection Technical` / `Inspection Executive`.
  - `src/components/inspection/InspectionPDFPreview.tsx`.
  - (Opcional) migration `service_order_reports`.
- **Risco:** baixo a médio (jspdf é sensível a layouts longos).
- **Validação:** geração de PDF com checklist real, fotos e assinatura.
- **Critérios de aceite:** PDF abre e imprime corretamente; tamanho < 10 MB típico.

### Fase 4 — Proposta com IA (P2)

- **Objetivo:** Edge `proposal-ai-draft` + `ProposalAIPanel`.
- **Arquivos:** `supabase/functions/proposal-ai-draft/index.ts`, `src/components/proposals/ProposalAIPanel.tsx`, hook.
- **Risco:** baixo (lê dados existentes, escreve só em jsonb metadata).
- **Critérios de aceite:** sugestão aparece em ≤ 20s; usuário consegue aceitar/rejeitar por seção.

### Fase 5 — Histórico de IA + Dashboard executivo (P3)

- **Objetivo:** migration `ai_conversations`/`ai_messages`; refactor `use-ai-agent` para persistir; `AIHistoryPage`; cards executivos no `Dashboard`.
- **Risco:** médio — alterar contrato do `ai-agent` (manter retro-compat).
- **Critérios de aceite:** todas as conversas novas persistem; conversas antigas em memória continuam funcionando até refresh; dashboard mantém todos KPIs atuais.

### Fase 6 — Assistente operacional ampliado + recomendações pro-ativas

- Cron diário `ai-proactive-scan` → `ai_recommendations`.
- Tools novas no `ai-agent`: `get_inspection`, `list_inspections`, `summarize_inspection`.
- Personalização via `user_settings` no system prompt.

---

## 7. ENTREGÁVEL 6 — Piloto Seguro Proposto

**Sim, há um piloto seguro** — exatamente a **Fase 1** descrita acima:

- **Não cria migration.**
- **Não cria Edge Function nova.**
- **Não chama Gemini.**
- **Não altera fluxo de OS, PDF, WhatsApp ou portal público.**
- **Não muda contrato de hooks existentes.**

Só adiciona UI nova atrás de uma TabsTrigger nova, com **feature flag local** (`const ENABLE_INSPECTION_TAB = false` por padrão até aprovação). Mesmo se aprovado, o pior caso é a aba ficar visível sem efeito colateral.

**Não vou implementar agora** — esta entrega termina como documentação. A Fase 1 só começa após o usuário revisar este blueprint e dar OK explícito.

---

## 8. Riscos Críticos a Lembrar

1. **Chave Gemini no client (no Gerador-de-Relatorios)** — NÃO portar. Toda chamada via Edge.
2. **Firebase / localStorage / Firestore** — NÃO portar. Adaptar para Supabase ou descartar.
3. **PII em logs** — `ai_generations.input_summary` deve omitir dados pessoais sensíveis (telefone, CPF). Resumir.
4. **Custo Gemini** — sem rate limit, multimodal pode estourar quota. `ai_rate_limits` é Fase A obrigatória.
5. **Variação de saída da IA** — relatório executivo pode variar entre execuções. Sempre marcar `prompt_version` para reproduzibilidade. Permitir edição manual.
6. **Conflito com `agenda_tasks`** — não criar `tasks` separadas do seawise-manager; usar agenda existente.
7. **Conflito com CRM atual** — não importar `leads` de seawise; MarineFlow já tem `CRMKanbanPage`.
8. **Envio automático ao cliente** — proibido na Fase 1–4. Sempre requer clique manual + modal de confirmação + audit log.
9. **Aprovação humana** — laudo só vira `signed` após técnico revisar; proposta só vira `external_quote` final após usuário aceitar sugestões; recomendações nunca disparam ação automática sem confirmação.
10. **Backward-compat do `ai-agent`** — não quebrar as 21 tools atuais nem o `AIAgentWidget`.

---

## 9. Recomendação Final da Primeira Implementação

**Implementar Fase 1 (piloto frontend read-only / mock) primeiro**, com base no checklist náutico do Gerador-de-Relatorios e no padrão `<Tabs>` já em `ServiceOrderDetail.tsx`. Custo baixíssimo, valida UX antes de qualquer migration, dá oportunidade ao usuário de ajustar o template antes de virar `inspection_templates` no banco. **Não tocar em IA, não tocar em DB, não tocar em PDF nesta primeira iteração.**

Após validação visual e aprovação, mover para Fase 2.

---

*Fim do blueprint.*
