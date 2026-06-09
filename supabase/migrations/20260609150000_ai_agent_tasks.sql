-- ai_agent_tasks: agent-scheduled follow-up tasks.
-- The agent creates tasks for itself: "check this quote in 48h",
-- "follow up with client about parts arrival", etc.
-- The hourly cron (ai-business-monitor) checks for due tasks and
-- surfaces them as alerts so the agent can act on them in the next session.

CREATE TABLE IF NOT EXISTS public.ai_agent_tasks (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  task_type           text        NOT NULL DEFAULT 'follow_up',
  title               text        NOT NULL,
  description         text        NOT NULL,
  due_at              timestamptz NOT NULL,
  entity_type         text,
  entity_id           uuid,
  entity_number       text,
  status              text        NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending', 'done', 'cancelled', 'snoozed')),
  priority            text        NOT NULL DEFAULT 'normal'
                                  CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  metadata            jsonb       NOT NULL DEFAULT '{}',
  created_by_agent    boolean     NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_agent_tasks_due_idx
  ON public.ai_agent_tasks (due_at, status)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ai_agent_tasks_entity_idx
  ON public.ai_agent_tasks (entity_id)
  WHERE entity_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_ai_agent_tasks_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER ai_agent_tasks_updated_at
  BEFORE UPDATE ON public.ai_agent_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_ai_agent_tasks_updated_at();

ALTER TABLE public.ai_agent_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_agent_tasks_read"
  ON public.ai_agent_tasks
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));
