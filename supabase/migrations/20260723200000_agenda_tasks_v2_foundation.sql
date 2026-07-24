-- =============================================================================
-- Agenda & Tarefas 2.0 — Fase 0 (Fundação)
-- Plano: plans/marineflow-agenda-tarefas.md
--
-- Evolui agenda_tasks (VAZIA em produção — verificado 23/07/2026) para o modelo
-- definitivo: tarefa (due_at) ≠ compromisso (hora marcada), responsável genérico,
-- vínculo polimórfico com o ERP, dedupe de automação, anti-conflito no banco.
-- Cria task_reminders e app_notifications. RLS: privacidade no SELECT/UPDATE/DELETE,
-- escrita autenticada (paridade com o resto do sistema; restore de backup insere
-- created_by de terceiros, então INSERT não pode exigir created_by = auth.uid()).
-- =============================================================================

-- 1) Extensão para EXCLUDE com uuid + range (anti double-booking)
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- 2) Rename controlado (tabela vazia; call sites atualizados no mesmo commit:
--    use-agenda.ts, AgendaPage.tsx, AgendaTaskDialog.tsx, tools/agenda.ts,
--    tools/field-ops.ts — NÃO confundir com technician_user_id legítimo de
--    service_order_expenses/services e time_entries, que não mudam)
ALTER TABLE public.agenda_tasks
  RENAME COLUMN technician_user_id TO assignee_user_id;
ALTER TABLE public.agenda_tasks
  RENAME CONSTRAINT agenda_tasks_technician_user_id_fkey TO agenda_tasks_assignee_user_id_fkey;

-- 3) Flexibilização + colunas novas
ALTER TABLE public.agenda_tasks
  ALTER COLUMN assignee_user_id DROP NOT NULL,
  ALTER COLUMN scheduled_start_at DROP NOT NULL,
  ADD COLUMN kind text NOT NULL DEFAULT 'task'
    CHECK (kind IN ('task','appointment')),
  ADD COLUMN due_at timestamptz,
  ADD COLUMN all_day boolean NOT NULL DEFAULT false,
  ADD COLUMN source text NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual','ai','automation','recurrence')),
  ADD COLUMN related_entity_type text
    CHECK (related_entity_type IS NULL OR related_entity_type IN (
      'service_order','quote','external_quote','client','vessel',
      'receivable','payable','purchase_order','collection','stock_item')),
  ADD COLUMN related_entity_id uuid,
  ADD COLUMN automation_key text,
  ADD COLUMN checklist jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN is_private boolean NOT NULL DEFAULT false,
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN completed_by uuid REFERENCES public.app_users(id),
  ADD COLUMN snoozed_until timestamptz,
  ADD COLUMN rrule text,
  ADD COLUMN recurrence_parent_id uuid REFERENCES public.agenda_tasks(id) ON DELETE CASCADE,
  ADD COLUMN origin_session_id uuid;

-- Compromisso precisa de horário de início
ALTER TABLE public.agenda_tasks
  ADD CONSTRAINT appointment_needs_start
    CHECK (kind <> 'appointment' OR scheduled_start_at IS NOT NULL);

-- 4) Anti-conflito NO BANCO: compromissos do mesmo responsável não se sobrepõem.
--    Só kind='appointment' com início+fim; tarefas não bloqueiam horário.
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

-- 5) Dedupe do motor de automações: uma tarefa VIVA por regra+entidade
CREATE UNIQUE INDEX agenda_tasks_automation_key_live
  ON public.agenda_tasks (automation_key)
  WHERE automation_key IS NOT NULL AND status IN ('pending','in_progress');

-- 6) Índices de leitura
CREATE INDEX agenda_tasks_assignee_due ON public.agenda_tasks (assignee_user_id, due_at)
  WHERE status IN ('pending','in_progress');
CREATE INDEX agenda_tasks_start ON public.agenda_tasks (scheduled_start_at)
  WHERE scheduled_start_at IS NOT NULL;
CREATE INDEX agenda_tasks_entity ON public.agenda_tasks (related_entity_type, related_entity_id)
  WHERE related_entity_id IS NOT NULL;

-- 7) RLS: privacidade real sem quebrar paridade nem restore.
--    Policies do mesmo comando combinam com OR — por isso NÃO usar FOR ALL aqui.
DROP POLICY IF EXISTS authenticated_all_agenda_tasks ON public.agenda_tasks;

CREATE POLICY agenda_tasks_select ON public.agenda_tasks FOR SELECT
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private
      OR assignee_user_id = auth.uid()
      OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM public.app_users u
                  WHERE u.id = auth.uid() AND u.role = 'admin' AND u.active)
    )
  );

CREATE POLICY agenda_tasks_insert ON public.agenda_tasks FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY agenda_tasks_update ON public.agenda_tasks FOR UPDATE
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private
      OR assignee_user_id = auth.uid()
      OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM public.app_users u
                  WHERE u.id = auth.uid() AND u.role = 'admin' AND u.active)
    )
  )
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY agenda_tasks_delete ON public.agenda_tasks FOR DELETE
  USING (
    auth.uid() IS NOT NULL AND (
      NOT is_private
      OR assignee_user_id = auth.uid()
      OR created_by = auth.uid()
      OR EXISTS (SELECT 1 FROM public.app_users u
                  WHERE u.id = auth.uid() AND u.role = 'admin' AND u.active)
    )
  );

-- 8) Lembretes (N por tarefa; processados pelo cron task-automations na Fase 2)
CREATE TABLE public.task_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.agenda_tasks(id) ON DELETE CASCADE,
  remind_at timestamptz NOT NULL,
  channel text NOT NULL DEFAULT 'app' CHECK (channel IN ('app','whatsapp')),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_reminders_due ON public.task_reminders (remind_at) WHERE sent_at IS NULL;
CREATE INDEX task_reminders_task ON public.task_reminders (task_id);

ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;
-- Visibilidade herdada da tarefa: o EXISTS respeita a RLS de agenda_tasks do caller
CREATE POLICY task_reminders_all ON public.task_reminders
  FOR ALL
  USING (auth.uid() IS NOT NULL
         AND EXISTS (SELECT 1 FROM public.agenda_tasks t WHERE t.id = task_id))
  WITH CHECK (auth.uid() IS NOT NULL
         AND EXISTS (SELECT 1 FROM public.agenda_tasks t WHERE t.id = task_id));

-- 9) Notificações in-app persistentes (substitui gradualmente o sino efêmero)
CREATE TABLE public.app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  navigate_to text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX app_notifications_user_unread
  ON public.app_notifications (user_id, created_at DESC) WHERE read_at IS NULL;

ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY app_notifications_select ON public.app_notifications FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY app_notifications_update ON public.app_notifications FOR UPDATE
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
-- INSERT/DELETE: somente service role (motor/lembretes) — sem policy de propósito.

-- 10) RPC unificada de conflito (tarefas + OS), usada por UI, tools de IA e motor.
--     SECURITY INVOKER (respeita RLS do caller; service role enxerga tudo).
CREATE OR REPLACE FUNCTION public.get_agenda_conflicts(
  p_user_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_task uuid DEFAULT NULL,
  p_exclude_so uuid DEFAULT NULL
) RETURNS TABLE (source text, ref_id uuid, label text, starts_at timestamptz, ends_at timestamptz)
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT 'task'::text, t.id, t.title, t.scheduled_start_at, t.scheduled_end_at
    FROM agenda_tasks t
   WHERE t.assignee_user_id = p_user_id
     AND t.kind = 'appointment'
     AND t.status IN ('pending','in_progress')
     AND t.id IS DISTINCT FROM p_exclude_task
     AND t.scheduled_start_at IS NOT NULL AND t.scheduled_end_at IS NOT NULL
     AND tstzrange(t.scheduled_start_at, t.scheduled_end_at) && tstzrange(p_start, p_end)
  UNION ALL
  SELECT 'service_order'::text, so.id, so.service_order_number, so.scheduled_start_at, so.scheduled_end_at
    FROM service_orders so
    JOIN service_order_technicians sot ON sot.service_order_id = so.id
   WHERE sot.user_id = p_user_id
     AND so.status <> 'cancelled'
     AND so.id IS DISTINCT FROM p_exclude_so
     AND so.scheduled_start_at IS NOT NULL AND so.scheduled_end_at IS NOT NULL
     AND tstzrange(so.scheduled_start_at, so.scheduled_end_at) && tstzrange(p_start, p_end);
$$;
