# 90 — Cross-check: documentação × código (Etapa 3)

Matriz dos 71 itens verificáveis (`[V-01]`..`[V-71]`) catalogados em `audit/01-inventario-docs.md`, classificados
contra o código e o banco reais.

Legenda: **✅ Implementado** · **🟡 Parcial** · **❌ Não implementado** · **↔️ Implementado diferente do planejado**
· **🗑️ Obsoleto (plano superado/abandonado)**

---

## 90.1 Documentos de operação

| Item | Afirmação do documento | Status | Evidência / achado |
|---|---|---|---|
| V-01 | `functions deploy` trava sem Docker; usar `--use-api` | ✅ | procedimento coerente com o deploy manual real (MF-AUD-057) |
| V-02 | project-ref canônico `okurngvcodmljjicopdp` | ✅ | confirmado: é o projeto com as 46 funções ACTIVE e as 278 migrations |
| V-03 | README = placeholder do Lovable | ✅ (é o defeito) | **MF-AUD-002** |
| V-12 | worktree isolado, nunca `git add -A` | ✅ | 15 worktrees em uso; migrations de 08/08 em `marineflow-erp--tokens` |
| V-13 | lógica de dimensionamento de cabo CC | ✅ | `src/lib/cable-sizing.test.ts`, RPC `dc_cable_sizing`, tabela `dc_ampacity_ratings` |
| V-14 | Evolution local + Cloudflare Quick Tunnel | ✅ | `infra/evolution/TUNNEL.md`; fragilidade conhecida e assumida |
| V-15 | 20 relatórios efêmeros versionados | ✅ (é o defeito) | **MF-AUD-003** |

## 90.2 `.lovable/plan.md` — o documento fundador do agente (25/04/2026)

| Item | Afirmação | Status | Evidência / achado |
|---|---|---|---|
| V-04 | Gemini 2.5 Pro via Lovable AI Gateway, `LOVABLE_API_KEY` | 🗑️ **obsoleto** | runtime usa **Claude via OpenRouter** (`_shared/ai/anthropic.ts:11,141`) — **MF-AUD-001** |
| V-05 | máx. 8 iterações de tool-calling | ↔️ | substituído por `maxIterations` + **orçamento de tempo** de 100 s (`agent.ts:59-62`) — proteção melhor |
| V-06 | `propose_action` antes de toda escrita | ↔️ | evoluiu para metadado `risk` + `computeRisk` + fila `ai_operator_pending_actions` + `confirm_action` determinístico |
| V-07 | 22 tools nominais | ↔️ | hoje são **188** — **MF-AUD-033** |
| V-08 | tokens Z-API no backend; envio via Z-API | 🗑️ obsoleto | Evolution é o provider default (`whatsapp/factory.ts:16`) |
| V-09 | validação Zod nas tools; nenhum SQL bruto | 🟡 | não há Zod nas Edge Functions (validação por JSON Schema + checagens manuais); "nenhum SQL bruto" ✅ |
| V-10 | `full_name_or_company_name`, `boat_name`, `product_name` | 🗑️ obsoleto | renomeados para `name` em `be13642`; nenhum resíduo em `src/` |
| V-11 | fora do escopo: histórico no banco, voz, lote | 🗑️ superado | todos existem hoje (`ai_operator_messages`, `agenda-voice-capture`, envio em fila) |

## 90.3 `docs/`

| Item | Afirmação | Status | Evidência / achado |
|---|---|---|---|
| V-16/V-17 | handoff congelado num bloqueio; instrui criar `evolution-debug` | ⚠️ | o bloqueio foi superado, mas a função de debug **continua ACTIVE em produção** — **MF-AUD-004**, **MF-AUD-055** |
| V-18 | "este arquivo não está commitado" | ❌ falso | está em `docs/` |
| V-19 | rollback para Z-API documentado | ✅ | `ZapiProvider` preservado como implementação alternativa — **não é código morto** |
| V-20 | agente migrado para Claude via OpenRouter | ✅ | confirmado no código |
| V-21 | secrets no Supabase | ✅ | tudo por `Deno.env.get`; nenhum literal |
| V-22 | canal WhatsApp interno com PIN | ✅ | `_shared/ai/whatsapp-pin.ts` + teste |
| V-23 | regras de devolução no Simples Nacional | ✅ | `nfe-info-complementar.ts` + teste; `_shared/fiscal/payload-builder.ts` |

## 90.4 Plano da Agenda (Fases 0-4, "CONCLUÍDAS")

| Item | Promessa | Status | Evidência |
|---|---|---|---|
| V-24 | rename `technician_user_id → assignee_user_id` propagado | ✅ | `AgendaPage.tsx:865`, `use-agenda.ts`, tools |
| V-25 | edge `scheduling-automations` apagada | 🟡 **meia verdade** | removida do repositório, **ACTIVE (v26) em produção** — **MF-AUD-055** |
| V-26 | constraint `btree_gist` anti double-booking | ✅ | `20260723200000_*.sql:14,59` |
| V-27 | motor com R1-R8, cron `*/15` | ✅ superado | 15 regras (`rules.ts:759`); cron ativo |
| V-28 | R9 nasce OFF, R10 existe | ✅ | `index.ts:212,161,255` |
| V-29 | 9 tools de agenda | 🟡 | são **8** — sem impacto funcional identificado |
| V-30 | briefing 07:30 | ✅ | cron `ai-daily-briefing` `30 10 * * *` UTC = 07:30 BRT |
| V-31 | semana mobile sem scroll horizontal | ✅ | `AgendaPage.tsx:891` |
| V-32 | `EntityTasksPanel` + **widget no Dashboard** | 🟡 | `EntityTasksPanel` ✅; **`DashboardTasksWidget` só existe no Dashboard legado** — **MF-AUD-050** |
| V-33 | Fase 4 (RRULE, drag-and-drop, snooze, BI) opcional | 🟡 | drag-and-drop existe (`onTaskDrop`); recorrência via `maintenance_plans` + `_shared/recurrence.ts` |

## 90.5 Plano de Compras & Cotação ("EM PRODUÇÃO")

| Item | Promessa | Status | Evidência |
|---|---|---|---|
| V-34 | `purchase-needs.ts` + 14 testes + hook | ✅ | arquivos e teste presentes |
| V-35 | `quote-comparison.ts` + 19 testes + telas | ✅ | presentes |
| V-36 | regras R16 e R17 | ✅ | `rules.ts:512`, `:692` |
| V-37 | `StockConfirmationDialog` substituído | ✅ | arquivo antigo não existe |
| V-38 | RLS de compras por cargo | ✅ | `20260730215125_rls_compras_por_cargo`; políticas granulares no banco |
| V-39 | `product_suppliers` preservada | ✅ | 4 pontos de uso confirmados |
| V-40 | em aberto: frete/desconto não persistem | 🟡 | declarado em aberto pelo plano; não reverificado |

## 90.6 Planos de conciliação e contexto vivo

| Item | Promessa | Status | Evidência |
|---|---|---|---|
| V-41 | `_shared/banking/{types,matching,quote-deposit}` | ✅ | presentes |
| V-42 | pesos 45/25/15/15 + bônus 12; tolerância 2%/R$50 | ✅ | `matching.ts` + 8 arquivos de teste |
| V-43 | `banking-reconcile`, `verify_jwt=false` com auth dupla | ✅ | confirmado; padrão documentado no `config.toml` |
| V-44 | 3 tools de banking com níveis de risco | ✅ | `_shared/ai/tools/banking.ts` |
| V-45 | "Suíte 304" testes | ✅ superado | hoje **842 testes / 70 arquivos, todos verdes** |
| V-46 | Fase 4 (memória de conciliação) não feita | ↔️ | `reconciliation_memory` + `remember_reconciliation` **existem** no banco — foi parcialmente adiantada |
| V-47 | F1 "livro das ignoradas" URGENTE | ✅ | `IgnoradasPanel` montado em `FinancialV2.tsx:613` |
| V-48 | estado único da linha bancária | 🟡 | não verificado em profundidade (fora do escopo desta passagem) |
| V-49 | `refresh_entity_open_loops()` no motor de 15 min | ✅ | tabela + view + regra R18 |
| V-50 | painel de fios soltos somente leitura | ✅ | `OpenLoopsPanel.tsx` |
| V-51 | título vira fio só dentro de 15 dias | 🟡 | regra existe na view; não reconferi o limiar |
| V-52 | tool `get_open_loops` | ✅ | `_shared/ai/tools/entity-360.ts` |
| V-53 | detector corrigido (status de OS inexistentes) | 🟡 **corrigido só ali** | a mesma lista fantasma sobreviveu em 4 outros lugares — **MF-AUD-005/006/007/008** |
| V-54 | ≥70% das mensagens com contato identificado | 🟡 | mecanismo presente (`resolve_contact_identity`, `unidentified_contacts`); métrica não medida nesta auditoria |
| V-55 | Fase 0.5 já existia com bugs | ✅ | auditoria embutida no plano, coerente com o código |
| V-56 | camada trocável `_shared/banking` | ✅ | presente |
| V-57 | segredos nunca no repo | ✅ | confirmado |
| V-58/59 | cartão tratado como transferência; correções pendentes | 🟡 | migrations de 08/08 já aplicadas em produção, ainda **fora da `main`** (worktree `--tokens`) — **MF-AUD-058** |

## 90.7 Planos de IA, execução de OS e propostas

| Item | Promessa | Status | Evidência |
|---|---|---|---|
| V-60 | 63 tools (21/07) | ↔️ | **188** hoje — **MF-AUD-033** |
| V-61 | Bloco B (voz→plano→confirmação) feito | ✅ | `agenda-voice-capture` + `VoiceCaptureButton` |
| V-62 | Blocos A, A′, C, D, E, F | 🟡 | A/D/E/F com contraparte no código (orçamento editável, compras, estoque, fiscal como tool); C (workflow `aprovar_orcamento`) não localizado como tal |
| V-63 | incidente HTTP 546 / teto de 150 s | ✅ resolvido | `timeBudgetMs` 100 s (`agent.ts:59-62`) |
| V-64 | modelo de dados do Ciclo do Serviço | ✅ | `service_order_steps`, `service_step_blocks/templates`, `service_surveys`, `survey_material_rules`, `service_cases`, `work_stop_reasons`, `time_entries` — todos existem |
| V-65 | telas: Quadro do Dia, Modo Foco, Painel do Roteiro, Levantamento | ✅ | `DayBoardPage.tsx`, `agenda/FocusMode.tsx`, `service-orders/StepFocusMode.tsx`, `ServiceRoutePanel.tsx`, `SurveyPanel.tsx` |
| V-66 | princípios operacionalizáveis (P6, P8/P18, P19, P21) | ✅ | `work_stop_reasons`, `estimate_from_cases`, rateio de miudezas em `materials-ops`, captura de diff em `ai_correction_patterns` |
| V-67 | Executivo Financeiro — proposta, 5 decisões pendentes | ❌ (correto) | não implementado, como o documento declara |
| V-68 | Transcrição de ligações — "nada foi construído" | ❌ (correto) | confirmado: nenhum código de transcrição de ligação |
| V-69 | Comunicação inteligente (Fases 0-3) | ✅ **implementado** | `_shared/ai/comms/` com 5 módulos e **5 testes** (`compliance-guard`, `exemplars`, `message-linter`, `reply-cadence`, `voice-profiles`) — o plano está mais atrasado que o código |
| V-70 | Contexto unificado (Ficha 360, resolução de contato, memória) | ✅ | `_shared/ai/tools/entity-360.ts`, `entity-memory.ts`, `resolve_contact_identity`, `ai_operator_memory_notes` |
| V-71 | Agenda autônoma (Fases 9-11) | ✅ | `agenda_suggestions`, `agenda-inbox-detector` (cron horário), `agenda-voice-capture`, `SuggestionCard`, `agenda_detector_exclusions` |

---

## 90.8 Achados de categoria B consolidados

| ID | Divergência | Severidade |
|---|---|---|
| **MF-AUD-001** | `.lovable/plan.md` descreve Gemini/Lovable; runtime é Claude/OpenRouter. Dois documentos vivos se contradizem | P2 |
| **MF-AUD-004** | `HANDOFF-EVOLUTION-CUTOVER.md` se apresenta como estado atual, congelado num bloqueio de junho, e instrui criar função de debug temporária | P2 |
| **MF-AUD-050** | 4 funcionalidades declaradas prontas (entre elas o widget de tarefas do `[V-32]`) não estão na UI servida | P1 |
| **MF-AUD-055** | `scheduling-automations` declarada apagada (`[V-25]`) continua ACTIVE em produção | P1 |
| **MF-AUD-033** | contrato de tools cresceu de 63 (`[V-60]`) para 188 sem revisão de custo | P2 |

---

## 90.9 Leitura geral do cross-check

Três padrões atravessam a matriz:

1. **O código costuma estar à frente da documentação, não atrás.** `[V-45]` (304 → 842 testes), `[V-27]`
   (8 → 15 regras), `[V-69]` (plano de comunicação já implementado), `[V-71]` (agenda autônoma entregue). Isto é
   incomum e é um bom sinal — o risco aqui é de documento obsoleto induzir ao erro, não de promessa não cumprida.
2. **As divergências reais estão sempre na fronteira repositório × produção**, não dentro do código: função
   declarada apagada que segue ACTIVE, migration aplicada sem arquivo, correção de RLS que só existe no banco.
   É o eixo de risco dominante deste projeto.
3. **Onde um plano declara "concluído", quase sempre está** — com uma exceção de padrão: itens que dependiam de
   estar **montados numa tela** (widget do Dashboard, painel de fluxo de caixa, extrato do cliente) se perderam
   na migração para a V2, sem que ninguém percebesse, porque o componente continua existindo e compilando.
