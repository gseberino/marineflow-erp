-- ai_workflows: tracks multi-step workflow instances per entity.
-- Each OS can have one active workflow at a time (UNIQUE on workflow_type + entity_id).
-- The agent advances steps; lifecycle hooks also advance steps on status changes.

CREATE TABLE IF NOT EXISTS public.ai_workflows (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_type    text        NOT NULL,
  -- 'quote_approval' | 'service_execution' | 'invoicing'
  entity_type      text        NOT NULL DEFAULT 'service_order',
  entity_id        uuid        NOT NULL,
  entity_number    text,
  client_id        uuid        REFERENCES public.clients(id) ON DELETE SET NULL,
  current_step     text        NOT NULL,
  steps_completed  text[]      NOT NULL DEFAULT '{}',
  status           text        NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active', 'completed', 'cancelled', 'paused')),
  context          jsonb       NOT NULL DEFAULT '{}',
  next_action_at   timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_type, entity_id)
);

CREATE INDEX IF NOT EXISTS ai_workflows_entity_idx
  ON public.ai_workflows (entity_id);

CREATE INDEX IF NOT EXISTS ai_workflows_active_idx
  ON public.ai_workflows (status, next_action_at)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS ai_workflows_client_idx
  ON public.ai_workflows (client_id)
  WHERE client_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_ai_workflows_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER ai_workflows_updated_at
  BEFORE UPDATE ON public.ai_workflows
  FOR EACH ROW EXECUTE FUNCTION public.set_ai_workflows_updated_at();

ALTER TABLE public.ai_workflows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_workflows_read"
  ON public.ai_workflows
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

CREATE POLICY "ai_workflows_write"
  ON public.ai_workflows
  FOR ALL
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()))
  WITH CHECK (private.ai_op_is_active(auth.uid()));
