# 15 — Agenda, Day Board e automações (Etapa 2, módulo 6)

Superfície: `src/pages/AgendaPage.tsx` (1.404 l), `src/pages/DayBoardPage.tsx`, `src/components/agenda/*` (13),
`src/components/AgendaTaskDialog.tsx`, `src/hooks/use-agenda.ts`, `supabase/functions/task-automations/`
(index.ts + rules.ts + rules_test.ts), `agenda-inbox-detector`, `agenda-voice-capture`,
`_shared/ai/tools/agenda.ts`, migrations `2026072*_agenda_*`.

---

## 15.0 Hipótese #5 do briefing: **CORRIGIDA**

A hipótese era "grid técnico×dia com overflow no mobile". O `WeekView` tem dois caminhos, e o de celular empilha
os dias em vez de montar a matriz:

```ts
// src/pages/AgendaPage.tsx:891 (dentro de WeekView)
// Mobile (< lg): dias empilhados — zero scroll horizontal (Princípio 0)
const mobileDays = days.map((d) => { … });
```
O grid técnico×dia só é renderizado a partir de `lg`. A única `grid-cols-N` sem breakpoint na tela é a do
calendário do mês (`:1148` — `grid grid-cols-7 gap-1`), que é semanticamente correta (sete dias) e encolhe os
pinos em vez de estourar.

---

## 15.1 Estado das promessas do plano `marineflow-agenda-tarefas.md` (Fases 0-4, declaradas concluídas)

| Item | Promessa | Status verificado |
|---|---|---|
| `[V-24]` | rename `technician_user_id → assignee_user_id` propagado | ✅ `use-agenda.ts`, `AgendaPage.tsx:865` (`t.assignee_user_id`), tools |
| `[V-25]` | edge `scheduling-automations` apagada | ✅ não existe em `supabase/functions/` |
| `[V-26]` | constraint `btree_gist` contra double-booking | ✅ `20260723200000_agenda_tasks_v2_foundation.sql:14,59` (`CREATE EXTENSION btree_gist`, `EXCLUDE USING gist`) |
| `[V-27]` | motor `task-automations` com R1-R8, cron `*/15` | ✅ e **superado**: `rules.ts:759` exporta 15 regras (`r1..r8, r11, r12, r14..r18`); cron `task-automations` ativo em `*/15 * * * *` |
| `[V-28]` | R9 nasce OFF, R10 existe | ✅ `index.ts:212` (`task_rule_r9_enabled ?? "false"`), `:161` (`r10 ?? "true"`), `:255` (`r13 ?? "false"`) |
| `[V-29]` | 9 tools de agenda para a IA | ⚠️ **8** em `_shared/ai/tools/agenda.ts` (`list_tasks`, `my_agenda`, `list_technicians`, `create_task`, `update_task`, `complete_task`, `delete_task`, `list_team_agenda`) |
| `[V-30]` | briefing 07:30 com "Sua agenda hoje" | ✅ cron `ai-daily-briefing` ativo em `30 10 * * *` UTC = **07:30 BRT** |
| `[V-31]` | semana mobile sem scroll horizontal | ✅ ver §15.0 |
| `[V-32]` | `EntityTasksPanel` + widget no Dashboard | ✅ `src/components/agenda/EntityTasksPanel.tsx`, `DashboardTasksWidget.tsx` |
| `[V-36]` | regras R16 e R17 (compras) no motor | ✅ `rules.ts:512` (R16), `:692` (R17) |
| `[V-49]` | `refresh_entity_open_loops()` dentro do motor de 15 min | ✅ tabela `entity_open_loops` + view `erp_open_loop_facts` presentes; regra R18 na lista |

A divergência de `[V-29]` (8 em vez de 9) é imaterial — o plano listava um conjunto pretendido, e a diferença
não corresponde a nenhuma funcionalidade ausente que eu tenha conseguido identificar. **Registro como observação,
não como achado.**

---

## 15.2 Achados

### [MF-AUD-039] Dropdown de OS do agendamento — ver [MF-AUD-005]
O achado que responde a hipótese #4 do briefing está no módulo 10 (`src/hooks/use-agenda.ts:163`), junto com os
outros três call sites da mesma lista de status inválidos. Repito aqui apenas o ponteiro para que o módulo da
Agenda não pareça limpo: **é o achado P1 deste módulo.**

### [MF-AUD-040] "Sem responsável" e outros rótulos da Agenda fora do i18n
- **Módulo:** Agenda + i18n
- **Arquivo:linha:** `src/pages/AgendaPage.tsx:885` (`full_name: 'Sem responsável'`) e mais 20 ocorrências no
  arquivo; `src/components/AgendaTaskDialog.tsx` (12 ocorrências, e o arquivo **não** importa `useI18n`)
- **Categoria:** E — **Severidade:** P3
- **Descrição:** A `AgendaPage` usa `useI18n` (inclusive `ag.weekdaysShort` para os dias da semana, corretamente),
  mas ainda tem 21 strings fixas em português. O `AgendaTaskDialog`, que é o diálogo principal do módulo, não
  passa pelo sistema. Caso particular do MF-AUD-028.
- **Evidência:**
  ```ts
  // AgendaPage.tsx:883-886 — linha sintética da matriz semanal
  return [ ...technicians, …, { id: '__unassigned__', full_name: 'Sem responsável' } ];
  ```
  ```ts
  // AgendaPage.tsx:835 — o caminho certo, no mesmo arquivo
  const WEEKDAYS = ag.weekdaysShort as string[];
  ```
- **Ação recomendada:** junto com MF-AUD-028; a Agenda é boa candidata a primeira conversão por ser uso diário.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-041] `AgendaPage.tsx` concentra 1.404 linhas com quatro visões e três subcomponentes no mesmo arquivo
- **Módulo:** Agenda
- **Arquivo:linha:** `src/pages/AgendaPage.tsx` — `WeekView` em `:821`, `MonthView` logo abaixo, mais o corpo da
  página, os filtros e o diálogo rápido
- **Categoria:** H — **Severidade:** P3
- **Descrição:** Cinco modos de visualização (`today | week | month | done | inbox`, `:50`) e os componentes de
  cada um convivem num arquivo só. Não encontrei bug decorrente — a lógica está organizada e memoizada
  (`useMemo` nos agrupamentos por técnico/dia, `:841-872`) —, mas é o segundo maior arquivo de página do
  repositório e o custo aparece na hora de mexer: o smoke test existente (`AgendaPage.smoke.test.tsx`) precisa
  mockar 8 hooks para renderizar.
- **Evidência:** `wc -l src/pages/AgendaPage.tsx` → 1.404; `grep "function .*View"` → `WeekView`, `MonthView`
  no mesmo arquivo.
- **Ação recomendada:** extrair `WeekView`/`MonthView` para `src/components/agenda/` quando houver outra razão
  para tocar o arquivo. Não é motivo para abrir uma tarefa sozinho.
- **Esforço:** M — **Decisão do Gustavo:** Não.

---

## 15.3 Verificações feitas que **não** produziram achado

- **Cron:** 17 jobs ativos no banco, todos conferidos contra as Edge Functions correspondentes. Os da Agenda:
  `task-automations` (`*/15`), `agenda-inbox-detector` (`20 * * * *`), `ai-daily-briefing` (`30 10 * * *` UTC).
- **Motor de automações:** 15 regras com teste (`rules_test.ts`), chave de deduplicação explícita
  (`keyOf(rule, entity, id, bucket)`, `rules.ts:41`), e a lição do CHECK de `agenda_tasks` documentada no
  cabeçalho da R17 (`:641`).
- **Toggles de regra:** regras que enviam WhatsApp respeitam `app_settings.task_rule_rN_enabled`, com R9 e R13
  **desligadas por padrão** e o canal interno exigindo `ai_whatsapp_enabled && phone_normalized`
  (`index.ts:186,325-326`) — nunca dispara para cliente por engano.
- **Conflito de agenda:** RPC única `get_agenda_conflicts` usada por UI, IA e motor (`use-agenda.ts:177-185`),
  com a decisão explícita de **não bloquear o salvamento** se a checagem falhar (`:184` — `if (error) return []`).
  Discutível, mas é escolha consciente e documentada.
- **Sobrecarga:** `overloadWarning` avisa acima de 8 h/dia sem bloquear (`use-agenda.ts:194-199`).

---

*Módulo 6 auditado. 2 achados próprios + 1 referência cruzada. Hipótese #5 do briefing: **corrigida**.*
