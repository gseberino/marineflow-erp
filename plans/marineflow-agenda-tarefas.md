# MarineFlow — Agenda & Tarefas 2.0

**Plano definitivo** · elaborado em 23/07/2026 · baseado em inspeção do repo canônico (`Claude Code/marineflow-erp`, branch `main`), introspecção do banco de produção (`okurngvcodmljjicopdp`) e benchmark de mercado.

---

## 1. Sumário executivo

**O fato que define este plano: a tabela `agenda_tasks` tem ZERO registros em produção.** A funcionalidade existe (página, dialog, 4 tools de IA) e ninguém a usa. Apenas 15 OS têm agendamento. O problema não é falta de calendário — é que a agenda atual é **passiva**: exige que alguém a alimente manualmente, não lembra ninguém de nada, e não conversa com o resto do sistema.

**A tese:** uma agenda só é usada quando ela **se alimenta sozinha e cobra resultado**. A Agenda & Tarefas 2.0 é construída sobre três pilares:

1. **Tarefas nascem do sistema** — OS aprovada sem agendamento, recebível vencendo, orçamento sem resposta, OC não recebida: cada evento relevante gera tarefa automaticamente (motor determinístico, com dedupe e auto-resolução quando a pendência some).
2. **O Agente IA é o operador da agenda** — cria, consulta, agenda OS com checagem de conflito, e entrega "sua agenda hoje" no briefing das 07:30 e sob demanda pelo WhatsApp interno ("me lembra de ligar pro Carlos amanhã 14h").
3. **Registro manual sem atrito** — visão "Hoje" estilo Todoist (atrasadas / do dia / sem data), checkbox de concluir direto no card, tarefa criada de dentro de qualquer tela (OS, cliente, orçamento) já vinculada à entidade.

**Diferencial vs mercado:** Jobber/ServiceTitan têm dispatch board; Motion/Reclaim têm auto-scheduling; Todoist tem captura rápida. Nenhum tem um funcionário IA no WhatsApp operando a agenda **sincronizada com financeiro, OS, orçamentos, compras e fiscal do próprio ERP** — tarefas que nascem e se resolvem sozinhas conforme o estado do negócio. É isso que vamos construir, sem a complexidade que não precisamos (sem GPS/rotas, sem Gantt, sem sync Google bidirecional).

---

## 2. Diagnóstico do estado atual (verificado em 23/07/2026)

### O que existe e funciona
| Item | Onde | Estado |
|---|---|---|
| Página Agenda (semana técnico×dia + mês) | `src/pages/AgendaPage.tsx` | Funcional, mas grade da semana tem `min-w-[700px]` + `overflow-x-auto` → **viola o Princípio 0 (zero scroll horizontal)** no mobile |
| Agendamento rápido de OS | `useQuickSchedule` em `src/hooks/use-agenda.ts` | Funcional: atualiza `service_orders.scheduled_start_at/end`, faz upsert de técnico, transição `pending→scheduled`, checa conflito (app-side) |
| Tarefas manuais | `agenda_tasks` + `AgendaTaskDialog.tsx` | Funcional e **nunca usada (0 linhas)** |
| Tools de IA | `supabase/functions/_shared/ai/tools/agenda.ts` | 4 tools: `list_agenda`, `list_technicians`, `create_agenda_task`, `update_agenda_task` — **sem checagem de conflito, sem delete, sem agendar OS, técnico obrigatório** |
| Crons ativos | `cron.job` (11 jobs) | `ai-daily-briefing` 07:30 BRT, `ai-business-monitor` de hora em hora, `ai-whatsapp-followups` 30min, `quote-reminders`, `receivable-reminders`, filas WhatsApp |
| WhatsApp interno da equipe | Fase 4 do AI Operator, LIVE | Canal pronto para lembretes e comandos de agenda |

### Dívidas e defeitos encontrados
1. **`scheduling-automations` está QUEBRADA e morta**: usa colunas antigas (`full_name_or_company_name`, `boat_name` — renomeadas no be13642) e não está no `cron.job`. Era o lembrete de agendamento para clientes. Será absorvida pelo novo motor (§6) com colunas corrigidas.
2. **`agenda_tasks.technician_user_id` é NOT NULL** → impossível criar tarefa para financeiro/admin/vendas. A tabela inteira assume "tarefa = coisa de técnico".
3. **`scheduled_start_at` é NOT NULL** → não existe tarefa sem horário marcado ("pagar imposto até sexta" não cabe no modelo). É a diferença entre calendário e gestão de tarefas.
4. **Zero vínculo com o resto do ERP**: só `client_id`. Nenhuma ligação com OS, orçamento, recebível, pagável, OC.
5. **Nenhum lembrete**: nada avisa ninguém de nada. O sino de notificações (`use-notifications.ts`) é 100% client-side, efêmero, estado de leitura em localStorage.
6. **RLS allow-all**: policy `authenticated_all_agenda_tasks` = qualquer autenticado faz tudo (mesmo padrão de dívida de `payments`/`bank_transactions`).
7. **Conflito só no app**: a checagem de sobreposição vive no hook React; a tool de IA e qualquer outro caminho de escrita não checam nada. Não há garantia no banco.
8. **`btree_gist` disponível mas não instalada** — necessária para a constraint anti-conflito (§5).

---

## 3. Benchmark — o que absorvemos e o que recusamos

Pesquisa: dispatch boards de field service (ServiceTitan, Jobber), auto-scheduling por IA (Motion, Reclaim.ai), gestão de tarefas (Todoist), padrões técnicos (RRULE/RFC 5545, exclusion constraints Postgres).

| Referência | O que absorvemos | O que recusamos (de propósito) |
|---|---|---|
| **Jobber** (SMB field service) | Dispatch semanal drag-and-drop; lembretes por mensagem que reduzem no-show | GPS tracking, precificação por usuário |
| **ServiceTitan** (enterprise) | Atribuição por disponibilidade + conflito; visão "quadro do dia" | Otimização de rota por tráfego, skills-matrix — complexidade de 20+ técnicos que a HBR não tem |
| **Motion / Reclaim.ai** | Conceito de tarefa com **deadline ≠ horário marcado**; aviso proativo de "em risco de atrasar" (via briefing IA) | Auto-scheduling total do calendário (time-blocking automático) — overkill e imprevisível para equipe de campo |
| **Todoist** | Visão "Hoje" (atrasadas + do dia); captura em linguagem natural (delegada ao Agente IA, sem lib de NLP) | Projetos/labels/karma — a "estrutura" aqui é o próprio ERP |
| **RFC 5545 (RRULE)** | Subconjunto: FREQ diária/semanal/mensal + intervalo + dias da semana + fim; materialização de 30 dias à frente | RRULE completa (BYSETPOS, EXDATE etc.) — "um projeto, não uma função" |
| **Postgres range types** | `EXCLUDE USING gist` com `tstzrange` — impossível double-booking de compromisso no nível do banco, imune a race condition | Checagem só na aplicação |

---

## 4. Arquitetura da solução

```
                    ┌─────────────────────────────┐
                    │        agenda_tasks          │
                    │  (tabela única, estendida)   │
                    │  kind: task | appointment    │
                    │  vínculo polimórfico c/ ERP  │
                    └──────────────┬──────────────┘
          escreve/resolve          │           lê/escreve
   ┌───────────────────────┐      │      ┌────────────────────────┐
   │  task-automations      │──────┼──────│  Agente IA (ai-agent)  │
   │  (edge fn, cron 15min) │      │      │  9 tools de agenda     │
   │  8 regras determinís-  │      │      │  briefing 07:30 +      │
   │  ticas, dedupe,        │      │      │  WhatsApp interno      │
   │  auto-resolução        │      │      └────────────────────────┘
   └───────────────────────┘      │
                    ┌──────────────┴──────────────┐
                    │        Frontend              │
                    │  Hoje | Semana | Mês         │
                    │  EntityTasksPanel (OS,       │
                    │  cliente, orçamento…)        │
                    │  Dashboard widget            │
                    └─────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │      task_reminders          │
                    │  processor → sino in-app +   │
                    │  WhatsApp INTERNO (fila já   │
                    │  existente)                  │
                    └─────────────────────────────┘
```

**Decisões definitivas de arquitetura:**

- **Uma tabela só (`agenda_tasks`), nome físico mantido.** Não renomear a tabela: o incidente be13642 provou que rename se propaga mal para Edge Functions. No domínio/UI chamamos de "Tarefas". Exceção controlada: renomear a **coluna** `technician_user_id → assignee_user_id` (tabela vazia, 4 arquivos de call sites, checklist de grep obrigatório em §11).
- **Motor de automações é determinístico, não-IA.** Regras em código (testáveis, versionadas), com liga/desliga em `app_settings`. A IA **não** cria tarefas por conta própria em background — ela cria quando solicitada em conversa e sugere no briefing. Isso evita duplicação e alucinação; o motor é quem garante que nada cai no chão.
- **Duas naturezas, um modelo**: `kind='task'` (coisa a fazer; pode ter só `due_at`, sem horário) e `kind='appointment'` (compromisso com hora marcada; sujeito à constraint anti-conflito). A OS agendada continua vivendo em `service_orders.scheduled_start_at` — a agenda LÊ as OS, não duplica (fonte única de verdade preservada).
- **Sincronização de mão dupla**: eventos do ERP criam tarefas (motor); resolução no ERP conclui tarefas (auto-resolução). Tarefa de "cobrar recebível" some sozinha quando o pagamento é registrado.
- **Lembrete chega onde a pessoa está**: sino in-app + WhatsApp **interno** (equipe, canal da Fase 4). Nenhuma mensagem nova para CLIENTE neste plano — lembretes a cliente continuam nos crons existentes (`quote-reminders`, `receivable-reminders`) e no conserto da `scheduling-automations`.

---

## 5. Modelo de dados definitivo

### 5.1 Migration principal (Fase 0)

```sql
-- 1) Extensão para a constraint anti-conflito
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2) Evolução da agenda_tasks (tabela está VAZIA — alterações livres)
ALTER TABLE public.agenda_tasks
  RENAME COLUMN technician_user_id TO assignee_user_id;

ALTER TABLE public.agenda_tasks
  ALTER COLUMN assignee_user_id DROP NOT NULL,          -- backlog sem dono é válido
  ALTER COLUMN scheduled_start_at DROP NOT NULL,        -- tarefa sem horário é válido
  ADD COLUMN kind text NOT NULL DEFAULT 'task'
    CHECK (kind IN ('task','appointment')),
  ADD COLUMN due_at timestamptz,                        -- deadline (≠ horário marcado)
  ADD COLUMN all_day boolean NOT NULL DEFAULT false,
  ADD COLUMN source text NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual','ai','automation','recurrence')),
  ADD COLUMN related_entity_type text
    CHECK (related_entity_type IN ('service_order','quote','external_quote','client',
      'vessel','receivable','payable','purchase_order','collection','stock_item')),
  ADD COLUMN related_entity_id uuid,
  ADD COLUMN automation_key text,                       -- dedupe do motor (§6)
  ADD COLUMN checklist jsonb NOT NULL DEFAULT '[]'::jsonb, -- [{text, done}]
  ADD COLUMN is_private boolean NOT NULL DEFAULT false,
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN completed_by uuid REFERENCES app_users(id),
  ADD COLUMN snoozed_until timestamptz,
  ADD COLUMN rrule text,                                -- subconjunto RFC 5545 (Fase 4)
  ADD COLUMN recurrence_parent_id uuid REFERENCES agenda_tasks(id) ON DELETE CASCADE,
  ADD COLUMN origin_session_id uuid;                    -- ai_operator_sessions, auditoria

-- status permanece: pending | in_progress | done | cancelled
-- CHECK de sanidade: tarefa precisa de ao menos uma âncora temporal OU ser backlog puro
ALTER TABLE public.agenda_tasks
  ADD CONSTRAINT appointment_needs_start
    CHECK (kind <> 'appointment' OR scheduled_start_at IS NOT NULL);

-- 3) Anti-conflito NO BANCO: dois compromissos do mesmo responsável não se sobrepõem.
--    Só para kind='appointment' com início+fim; tasks e itens sem fim não bloqueiam.
ALTER TABLE public.agenda_tasks
  ADD CONSTRAINT no_overlapping_appointments
  EXCLUDE USING gist (
    assignee_user_id WITH =,
    tstzrange(scheduled_start_at, scheduled_end_at) WITH &&
  )
  WHERE (kind = 'appointment'
         AND status NOT IN ('cancelled','done')
         AND assignee_user_id IS NOT NULL
         AND scheduled_start_at IS NOT NULL
         AND scheduled_end_at IS NOT NULL);

-- 4) Dedupe do motor: uma tarefa viva por regra+entidade
CREATE UNIQUE INDEX agenda_tasks_automation_key_live
  ON public.agenda_tasks (automation_key)
  WHERE automation_key IS NOT NULL AND status IN ('pending','in_progress');

-- 5) Índices de leitura (padrões de acesso: por dia, por dono, por entidade)
CREATE INDEX agenda_tasks_assignee_due   ON agenda_tasks (assignee_user_id, due_at)
  WHERE status IN ('pending','in_progress');
CREATE INDEX agenda_tasks_start          ON agenda_tasks (scheduled_start_at)
  WHERE scheduled_start_at IS NOT NULL;
CREATE INDEX agenda_tasks_entity         ON agenda_tasks (related_entity_type, related_entity_id);

-- 6) Lembretes (N por tarefa, canal explícito)
CREATE TABLE public.task_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES agenda_tasks(id) ON DELETE CASCADE,
  remind_at timestamptz NOT NULL,
  channel text NOT NULL DEFAULT 'app' CHECK (channel IN ('app','whatsapp')),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_reminders_due ON task_reminders (remind_at) WHERE sent_at IS NULL;

-- 7) Notificações in-app persistentes (substitui gradualmente o sino efêmero)
CREATE TABLE public.app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_users(id),
  type text NOT NULL,               -- 'task_reminder','task_assigned','task_overdue',…
  title text NOT NULL,
  body text,
  navigate_to text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX app_notifications_user_unread ON app_notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;
```

### 5.2 RLS definitiva (mesma migration) — REVISADA 23/07/2026

Fatos verificados que mudaram o desenho original: (a) nem todo `app_users` tem login —
técnicos como Felipe não existem em `auth.users`, então comparações com `auth.uid()` só
funcionam para quem loga; (b) TODAS as tabelas de negócio hoje são allow-all autenticado
(`authenticated_all_*`) — RLS por dono numa tabela só criaria postura inconsistente sem
ganho real; (c) o restore de backup (`MasterDataManagement.tsx`) insere linhas com
`created_by` de terceiros — `WITH CHECK (created_by = auth.uid())` quebraria o restore.

**Decisão:** proteger o que importa (tarefas privadas) e manter paridade no resto.
RLS por dono/papel entra na dívida global de RLS (plano de otimização), tabela inteira.

```sql
DROP POLICY authenticated_all_agenda_tasks ON public.agenda_tasks;

-- Expressão de visibilidade (repetida nas policies — Postgres não tem "macro"):
--   NOT is_private OR assignee_user_id = auth.uid() OR created_by = auth.uid()
--   OR (admin ativo)
-- ATENÇÃO: policies do mesmo comando combinam com OR — por isso NÃO usar FOR ALL
-- (uma FOR ALL permissiva anularia a privacidade do SELECT).

CREATE POLICY agenda_tasks_select ON public.agenda_tasks FOR SELECT
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private
      OR assignee_user_id = auth.uid()
      OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid()
                   AND u.role = 'admin' AND u.active)
    )
  );

-- INSERT: paridade com o resto do sistema (restore-safe: backup insere created_by alheio)
CREATE POLICY agenda_tasks_insert ON public.agenda_tasks FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- UPDATE/DELETE: espelham a visibilidade — ninguém edita/apaga o que não pode ver
CREATE POLICY agenda_tasks_update ON public.agenda_tasks FOR UPDATE
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private OR assignee_user_id = auth.uid() OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid()
                   AND u.role = 'admin' AND u.active)
    )
  ) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY agenda_tasks_delete ON public.agenda_tasks FOR DELETE
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private OR assignee_user_id = auth.uid() OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM app_users u WHERE u.id = auth.uid()
                   AND u.role = 'admin' AND u.active)
    )
  );

-- task_reminders: visibilidade herdada da tarefa (EXISTS na agenda_tasks)
-- app_notifications: SELECT/UPDATE só do próprio user_id; INSERT via service role
-- Escrita do motor e da IA: service role (bypassa RLS), como nas demais ai_operator_*
```

### 5.3 RPC unificada de conflito (usada por UI e IA — hoje cada um checa de um jeito)

```sql
CREATE OR REPLACE FUNCTION public.get_agenda_conflicts(
  p_user_id uuid, p_start timestamptz, p_end timestamptz, p_exclude_task uuid DEFAULT NULL,
  p_exclude_so uuid DEFAULT NULL
) RETURNS TABLE (source text, ref_id uuid, label text, starts_at timestamptz, ends_at timestamptz)
LANGUAGE sql STABLE AS $$
  SELECT 'task', t.id, t.title, t.scheduled_start_at, t.scheduled_end_at
    FROM agenda_tasks t
   WHERE t.assignee_user_id = p_user_id AND t.kind = 'appointment'
     AND t.status IN ('pending','in_progress')
     AND t.id IS DISTINCT FROM p_exclude_task
     AND tstzrange(t.scheduled_start_at, t.scheduled_end_at) && tstzrange(p_start, p_end)
  UNION ALL
  SELECT 'service_order', so.id, so.service_order_number, so.scheduled_start_at, so.scheduled_end_at
    FROM service_orders so
    JOIN service_order_technicians sot ON sot.service_order_id = so.id
   WHERE sot.user_id = p_user_id AND so.status <> 'cancelled'
     AND so.id IS DISTINCT FROM p_exclude_so
     AND so.scheduled_start_at IS NOT NULL AND so.scheduled_end_at IS NOT NULL
     AND tstzrange(so.scheduled_start_at, so.scheduled_end_at) && tstzrange(p_start, p_end);
$$;
```

> Nota: a EXCLUDE constraint cobre `agenda_tasks × agenda_tasks` no nível do banco (garantia dura). O conflito cruzado tarefa×OS é coberto pela RPC (garantia de aplicação, chamada por TODOS os caminhos de escrita: hook web, tool de IA, motor).

---

## 6. Motor de automações (`task-automations`)

**Edge Function nova, cron `*/15 * * * *`** (mesmo padrão de `fiscal-reconcile`), com `CRON_SECRET`. Regras em código (`supabase/functions/task-automations/rules.ts`), cada uma com testes Deno. Liga/desliga e parâmetros por regra em `app_settings` (`task_rule_<id>_enabled`, `task_rule_<id>_days`).

### Regras v1 (8 regras)

| # | Regra | Condição | Tarefa criada (assignee) | `automation_key` | Auto-resolução quando |
|---|---|---|---|---|---|
| R1 | OS aprovada sem agenda | `status='approved'` e `scheduled_start_at IS NULL` há > 24h | "Agendar OS {n} — {cliente}" (admin) | `r1:so:{id}` | OS ganha `scheduled_start_at` ou é cancelada |
| R2 | OS parada | `status='in_progress'` sem update há > 3 dias | "Verificar OS {n} parada há {d} dias" (admin) | `r2:so:{id}:{semana}` | OS muda de status ou é atualizada |
| R3 | Recebível vencendo | `due_date` entre hoje e D+3, não pago | "Cobrar {cliente} — R$ {valor} vence {data}" (financeiro) | `r3:recv:{id}` | Recebível pago/cancelado |
| R4 | Recebível VENCIDO | `due_date < hoje`, não pago | "URGENTE: {cliente} em atraso — R$ {valor}" (financeiro, priority=urgent) | `r4:recv:{id}` | Recebível pago/cancelado |
| R5 | Pagável vencendo | `due_date` ≤ D+1, não pago | "Pagar {fornecedor} — R$ {valor}" (financeiro) | `r5:pay:{id}` | Pagável pago/cancelado |
| R6 | Orçamento sem resposta | `quote_status='sent'` há > 3 dias | "Follow-up orçamento {n} — {cliente}" (vendedor criador) | `r6:quote:{id}` | quote_status muda |
| R7 | OC não recebida | `status='ordered'` há > prazo do fornecedor (default 7d) | "Cobrar entrega OC {n} — {fornecedor}" (admin) | `r7:po:{id}` | OC recebida/cancelada |
| R8 | Estoque mínimo | `stock_quantity < min_stock` | "Repor {produto} (atual: {q}, mín: {min})" (admin) | `r8:prod:{id}` | Estoque ≥ mínimo |

**Mecânica (idempotente e reversível):**
1. Para cada regra habilitada, calcular o conjunto de entidades em condição.
2. `INSERT ... ON CONFLICT` não existe para índice parcial → usar upsert manual: tentar insert; se violar `agenda_tasks_automation_key_live`, ignorar (tarefa viva já existe). Se existir tarefa `done` para a mesma key e a condição voltou (ex.: OS reaberta), criar nova (a key só é única entre tarefas VIVAS).
3. **Auto-resolução:** para cada tarefa viva com `automation_key`, reavaliar a condição da regra; se resolvida, `status='done'`, `completed_at=now()`, nota "Resolvido automaticamente: {motivo}". Ninguém fecha tarefa que o sistema já sabe que acabou.
4. Toda criação/resolução vai para `ai_operator_audit` (trilha já existente).

**Absorção da `scheduling-automations` (quebrada):** o lembrete de OS a CLIENTE (D-1, WhatsApp) é reescrito dentro do motor como R9, com colunas corrigidas (`clients.name`, `vessels.name`), usando `reminder_sent_at` e a fila `whatsapp_send_queue` existente com test-mode preservado. A function antiga é apagada. R9 nasce **desabilitada** por padrão — mensagem a cliente exige ativação explícita do usuário (regra de autorização do CLAUDE.md).

**Lembrete interno de OS ao técnico:** R10 — OS agendada para amanhã → lembrete WhatsApp interno ao(s) técnico(s) na véspera às 17h + no dia às 07:00 (via `task_reminders`, não mensagem a cliente). Habilitada por padrão só para quem tem `ai_whatsapp_enabled=true`.

---

## 7. Lembretes e notificações

**Processor de lembretes:** o mesmo cron `task-automations` (a cada 15min) processa `task_reminders WHERE remind_at <= now() AND sent_at IS NULL`:
- `channel='app'` → insere em `app_notifications` (sino).
- `channel='whatsapp'` → enfileira em `whatsapp_send_queue` **apenas se o destinatário é app_user com `ai_whatsapp_enabled=true`** (canal interno da Fase 4). Nunca cliente.
- Marca `sent_at` (at-least-once com trava otimista: `UPDATE ... WHERE sent_at IS NULL RETURNING`).

**Sino v2:** `use-notifications.ts` passa a mesclar as notificações computadas atuais + `app_notifications` persistentes (novo hook `useAppNotifications` com Realtime subscription). Estado de leitura sai do localStorage para `read_at`. As notificações computadas de OS/recebível vão sendo aposentadas conforme as regras R1–R8 as substituem com tarefa acionável (melhor que aviso).

**Defaults de lembrete (sem configuração obrigatória):** compromisso ganha lembrete automático app 30min antes; tarefa com `due_at` ganha lembrete app às 08:00 do dia do vencimento. Usuário pode adicionar/remover no dialog.

---

## 8. IA — o Agente como operador da agenda

### 8.1 Tool set definitivo (substitui as 4 atuais em `_shared/ai/tools/agenda.ts`)

| Tool | Descrição | Risk |
|---|---|---|
| `list_tasks` | Filtros: assignee, período (due OU scheduled), status, prioridade, entidade relacionada, origem. Retorna também atrasadas. | low |
| `my_agenda` | Agenda consolidada de um usuário/dia: tarefas due + compromissos + OS agendadas + (se financeiro/admin) vencimentos do dia. É a tool do "minha agenda hoje". | low |
| `create_task` | Cria task/appointment; aceita `related_entity`, checklist, lembretes (`reminders: [{offset_minutes, channel}]`), `due_at` ou horário. **Chama `get_agenda_conflicts` antes** se appointment; se conflitar, retorna os conflitos para o modelo decidir/perguntar. Grava `source='ai'` + `origin_session_id`. | low |
| `update_task` | Reagendar, reatribuir, editar checklist, snooze. Mesma checagem de conflito. | low |
| `complete_task` | Conclui com nota opcional. | low |
| `delete_task` | Exclui (só criadas manualmente/por IA; tarefas de automação são canceladas, não apagadas — o motor as recriaria). | medium |
| `check_availability` | Slots livres de um usuário num intervalo (usa `get_agenda_conflicts` + horário comercial 08–18). | low |
| `schedule_service_order` | **Paridade com o QuickSchedule da UI** (hoje a IA não sabe agendar OS): técnico + início/fim, conflito via RPC, transição `pending→scheduled`, upsert em `service_order_technicians`. | low |
| `list_team_agenda` | Grade do dia/semana da equipe inteira (para "como está a agenda da equipe amanhã?"). Técnico não vê tarefas privadas de outros (filtro no execute, padrão `blockTechnician` existente). | low |

Riscos seguem a recalibração de 14/07: back-office = low (executa direto); nada aqui é high. `delete_task` = medium (pendência de aprovação).

### 8.2 Prompt e comportamento
- `prompt.ts` ganha seção "Agenda & Tarefas": quando o usuário pedir lembrete/tarefa/agendamento em linguagem natural, resolver datas relativas ("amanhã", "sexta") no fuso **America/Sao_Paulo**, usar `check_availability` antes de marcar compromisso com hora, e SEMPRE vincular à entidade quando o contexto tiver uma (ex.: conversa sobre OS-123 → `related_entity`).
- A IA **sugere** tarefas em conversa ("quer que eu crie uma tarefa de follow-up?") mas criação automática em background é exclusiva do motor (§4, decisões).

### 8.3 Briefing 07:30 e WhatsApp interno
- `ai-daily-briefing` ganha bloco **"📋 Sua agenda hoje"** por destinatário: atrasadas (com dias), compromissos/OS do dia com horário, tarefas due hoje, e "em risco" (due amanhã com dependência aberta — conceito Motion de at-risk).
- Comandos naturais no WhatsApp interno já funcionam via tools: "minha agenda", "o que tenho amanhã?", "me lembra de X às 15h", "agenda a OS 145 pro Pedro sexta 9h". Nenhum parser novo — é o mesmo `ai-agent`.

---

## 9. UI/UX — especificação

### 9.1 AgendaPage v2 — três visões
- **Hoje** (nova, vira a default): três grupos — **Atrasadas** (vermelho, contador), **Hoje** (ordenado: compromissos com hora primeiro, depois tasks por prioridade), **Sem data** (backlog). Checkbox de concluir direto no card (optimistic update). Filtro: "Minhas | Equipe | por pessoa".
- **Semana** (evolução da atual): grade pessoa×dia (não só técnicos — qualquer app_user ativo com tarefa/OS na semana + técnicos fixos). **Mobile: sem grade** — accordion de dias (Princípio 0: zero scroll horizontal; a grade atual com `min-w-[700px]` é substituída em telas < lg por lista empilhada por dia).
- **Mês** (mantida como está, + pontos de cor por prioridade).

### 9.2 Card de tarefa (todas as visões)
`[checkbox] Título · chip de entidade (→ navega: "OS-145", "R$ 2.300 vence 25/07") · avatar do responsável · badge de origem (🤖 IA / ⚙️ Auto / ✋ Manual) · horário ou due · checklist 2/5`

### 9.3 TaskDialog v2
Campos: título; tipo (tarefa/compromisso — alterna entre `due_at` e início/fim); responsável (qualquer usuário ativo, default eu); prioridade; entidade relacionada (combobox por tipo, pré-preenchida quando aberto de dentro de uma tela); checklist; lembretes (chips: "30min antes", "1 dia antes", "custom" + canal app/WhatsApp); privada; recorrência (Fase 4). Erro de conflito mostra os compromissos conflitantes retornados pela RPC com link.

### 9.4 Integração nas telas do ERP (o "sincronizado com tudo")
- **`EntityTasksPanel`** (componente único, ~150 linhas): lista tarefas vivas + concluídas recentes da entidade + botão "Nova tarefa" pré-vinculada. Embutido em: detalhe de OS, detalhe de cliente, detalhe de orçamento externo, tela financeira (aba), OC.
- **Dashboard**: widget "Hoje" (contadores: atrasadas / hoje / da equipe) com link para a Agenda.
- **Tarefa acionável**: tarefa com entidade ganha botão de atalho da ação que a resolve (R3/R4 → "Registrar pagamento" deep-link; R1 → abre QuickSchedule com a OS pré-selecionada). A tarefa não é um aviso — é um botão para resolver.

### 9.5 O que NÃO entra na UI v1
Drag-and-drop (Fase 4, com @dnd-kit), visão timeline por hora, impressão, cores customizadas, tarefas de cliente no portal.

---

## 10. Sincronização — matriz módulo × agenda

| Módulo | Sistema → Agenda | Agenda → Sistema |
|---|---|---|
| **OS** | R1 (aprovada sem agenda), R2 (parada), R10 (lembrete técnico); OS agendadas aparecem na grade (leitura direta, sem duplicar) | `schedule_service_order` / QuickSchedule agendam e transicionam status; concluir tarefa R1 sugere abrir agendamento |
| **Financeiro** | R3/R4 (recebível), R5 (pagável); auto-resolve no pagamento | Atalho "Registrar pagamento" na tarefa |
| **Orçamentos** | R6 (follow-up interno; complementa `quote-reminders` que fala com o cliente) | Atalho abre o orçamento |
| **Compras** | R7 (OC atrasada); auto-resolve no recebimento | Atalho "Receber OC" |
| **Estoque** | R8 (mínimo); auto-resolve na reposição | Atalho "Criar OC" |
| **Fiscal** | (v2, fora do escopo v1: NF rejeitada → tarefa) | — |
| **CRM/Prospecção** | (v2: lead sem contato há N dias) | — |
| **WhatsApp interno** | Lembretes + briefing com agenda | Comandos naturais criam/consultam/agendam |

---

## 11. Fases de execução

> Todas as fases: desenvolvimento em **worktree isolado** (skill `multi-session-guard` — repo tem sessões paralelas), staging por arquivo (nunca `git add -A`), `deno test` + `npm run build` verdes antes de merge, migration de produção **nomeada e autorizada explicitamente** antes de aplicar (gate padrão do projeto).

### Fase 0 — Fundação (1 sessão)
Migration §5 completa (schema + RLS + RPC + `btree_gist`) · atualizar `types.ts` (edição manual da seção `agenda_tasks` + novas tabelas, para manter o diff estreito — regen completo puxaria drift de outras frentes) · propagar rename `technician_user_id→assignee_user_id` — **checklist obrigatório de grep** (lição be13642), call sites CONFIRMADOS em 23/07: `use-agenda.ts`, `AgendaPage.tsx`, `AgendaTaskDialog.tsx`, `_shared/ai/tools/agenda.ts`, `_shared/ai/tools/field-ops.ts` (tool `technician_day_agenda`) · NÃO mudam: `service_order_expenses/services.technician_user_id`, `time_entries.technician_user_id` (colunas legítimas de outras tabelas), `service_order_technicians.user_id`, `MasterDataManagement.tsx` (export/import dinâmico) · nenhuma view/função SQL referencia `agenda_tasks` (verificado) · apagar `scheduling-automations` (morta) · testes da RPC.
**Aceite:** app atual funciona igual (nenhuma feature nova visível); criar/editar tarefa manual segue funcionando; constraint rejeita double-booking em teste SQL.

### Fase 1 — Tarefas de verdade na UI (1–2 sessões)
Visão Hoje (default) · TaskDialog v2 · checkbox concluir · chips de entidade · `EntityTasksPanel` em OS/cliente/orçamento · widget no Dashboard · semana mobile sem scroll horizontal.
**Aceite:** criar tarefa de dentro de uma OS em ≤ 3 cliques; concluir em 1; mobile sem barra lateral; tarefas privadas invisíveis para outros não-admin.

### Fase 2 — Motor + lembretes (1–2 sessões)
Edge function `task-automations` com R1–R8 + auto-resolução + dedupe (testes Deno por regra) · processor de `task_reminders` · `app_notifications` + sino v2 · R9 (cliente, nasce OFF) e R10 (técnico) · toggles em Settings · cron `*/15` (agendamento do cron = gate explícito com o usuário, mesmo padrão da Fase 5 do AI Operator).
**Aceite:** recebível de teste vencendo gera tarefa em ≤ 15min; pagamento a resolve sozinho; nenhuma duplicata após 4 execuções seguidas; lembrete WhatsApp chega só a usuário interno habilitado.

### Fase 3 — IA operadora (1 sessão)
9 tools (§8.1) substituem as 4 · prompt · briefing com "Sua agenda hoje" · validação E2E via WhatsApp interno (mesmo método sintético da Fase 4 do AI Operator).
**Aceite:** "me lembra de ligar pro Carlos amanhã 14h" cria tarefa com lembrete; "agenda a OS X pro Pedro sexta 9h" agenda com checagem de conflito; "minha agenda" responde consolidado.

### Fase 4 — Refinos (1 sessão, opcional/posterior)
Recorrência (subconjunto RRULE, materialização 30d no cron diário, editar série vs ocorrência) · drag-and-drop na semana (@dnd-kit) · snooze na UI · métricas no BI (concluídas/atrasadas por pessoa/semana) · regras fiscal + CRM (matriz §10).

**Total estimado: 4–6 sessões de trabalho.** Fases 0→3 formam o produto completo; Fase 4 é lapidação.

---

## 12. Não-objetivos (explícitos, para manter o "não complexo")

Sem sync bidirecional Google/Outlook (avaliar export .ics somente-leitura depois) · sem otimização de rotas/GPS · sem time-tracking · sem dependências entre tarefas/Gantt · sem RRULE completa · sem agendamento self-service pelo cliente · sem app mobile separado (a web responsiva cobre) · sem auto-scheduling estilo Motion (a IA sugere, humano confirma horário).

---

## 13. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Rename de coluna se propagar mal (padrão be13642) | Tabela vazia + checklist de grep na Fase 0 + deploy migration e código no mesmo merge |
| Sessões paralelas no repo sobrescreverem trabalho | Worktree isolado (`multi-session-guard`) + staging por arquivo |
| Motor criar tarefa em loop/duplicada | Índice único parcial em `automation_key` + testes de idempotência (4 execuções seguidas = 0 duplicatas) |
| Mensagem indevida a cliente | R9 nasce OFF; canal WhatsApp de lembretes só aceita `app_users` com `ai_whatsapp_enabled`; test-mode preservado |
| EXCLUDE constraint bloquear caso legítimo (2 técnicos juntos na mesma OS) | Constraint só em `agenda_tasks` kind='appointment' por responsável; OS não entra na constraint (join table permite N técnicos) |
| Fuso horário (datas relativas da IA, DST não existe no BR mas UTC confunde) | Tudo `timestamptz`; prompt fixa America/Sao_Paulo; testes com datas de borda (23:00 BRT = dia seguinte UTC) |
| Infra WhatsApp frágil (histórico Evolution/túnel) | Lembrete WhatsApp é best-effort com fallback garantido no sino in-app; `sent_at` só marca após enqueue OK |

---

## 14. Métricas de sucesso (medir 30 dias após Fase 3)

1. **Adoção:** ≥ 20 tarefas vivas/semana (hoje: 0).
2. **Autoalimentação:** ≥ 50% das tarefas com `source IN ('automation','ai')`.
3. **Fechamento de ciclo:** ≥ 60% das tarefas de automação resolvidas (auto ou manual) em ≤ 7 dias.
4. **Zero incidente** de mensagem a cliente originada deste plano.
5. **Uso pela IA:** comandos de agenda no WhatsApp interno ≥ 3/semana.

---

## Referências da pesquisa

- Dispatch/field service: [ServiceTitan — technician scheduling best practices](https://www.servicetitan.com/blog/service-technician-scheduling), [dispatch software](https://www.servicetitan.com/features/dispatch-software), [comparativo Jobber/ServiceTitan](https://fieldservicesoftware.io/best-field-service-software/best-job-scheduling-software-for-field-service-management/)
- AI scheduling: [Motion — AI task manager](https://www.usemotion.com/features/ai-task-manager), [Reclaim — como funciona o auto-scheduling](https://help.reclaim.ai/en/articles/6207587-how-reclaim-manages-your-schedule-automatically), [prioridades no Reclaim](https://help.reclaim.ai/en/articles/4292868-using-priorities-to-control-how-tasks-get-scheduled)
- Anti-conflito em Postgres: [range types + exclusion constraints](https://www.jusdb.com/blog/postgresql-range-types-exclusion-constraints), [GiST/EXCLUDE na prática](https://www.red-gate.com/simple-talk/databases/postgresql/overlapping-ranges-in-subsets-in-postgresql/), [padrão com WHERE not cancelled](https://peterullrich.com/prevent-overlapping-schedules-with-ecto-and-postgres)
- Recorrência: [RRULE/RFC 5545 na prática](https://www.nylas.com/blog/calendar-events-rrules/), [estratégia híbrida regra+materialização](https://www.codegenes.net/blog/calendar-recurring-repeating-events-best-storage-method/)
