-- ai_agent_memory: structured persistent memory for the AI agent.
-- Stores factual notes about clients, vessels, OS patterns, and business insights.
-- Agent reads via search_memory tool; writes via save_memory tool.

CREATE TABLE IF NOT EXISTS public.ai_agent_memory (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scope               text        NOT NULL
                                  CHECK (scope IN ('global', 'client', 'vessel', 'service_order', 'operator')),
  entity_id           uuid,
  entity_name         text,
  memory_key          text        NOT NULL,
  memory_value        text        NOT NULL,
  confidence          text        NOT NULL DEFAULT 'high'
                                  CHECK (confidence IN ('high', 'medium', 'low')),
  source              text,
  created_by_user_id  uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Fast lookup by entity
CREATE INDEX IF NOT EXISTS ai_agent_memory_entity_idx
  ON public.ai_agent_memory (entity_id)
  WHERE entity_id IS NOT NULL;

-- Fast lookup by scope
CREATE INDEX IF NOT EXISTS ai_agent_memory_scope_idx
  ON public.ai_agent_memory (scope, memory_key);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_ai_agent_memory_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER ai_agent_memory_updated_at
  BEFORE UPDATE ON public.ai_agent_memory
  FOR EACH ROW EXECUTE FUNCTION public.set_ai_agent_memory_updated_at();

ALTER TABLE public.ai_agent_memory ENABLE ROW LEVEL SECURITY;

-- Active authenticated users can read all memories
CREATE POLICY "ai_memory_read"
  ON public.ai_agent_memory
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));
