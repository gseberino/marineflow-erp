-- ai_correction_patterns: structured log of corrections to agent proposals.
-- When an operator rejects a proposal and provides a correction, the agent
-- saves it here. Future sessions load relevant patterns before proposing.

CREATE TABLE IF NOT EXISTS public.ai_correction_patterns (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  correction_type  text        NOT NULL,
  -- 'price_too_high' | 'price_too_low' | 'wrong_client' | 'wrong_service'
  -- | 'format_preference' | 'workflow_preference' | 'message_tone' | 'other'
  context          text        NOT NULL,  -- brief description of what was proposed
  original_value   text,                  -- what the agent proposed
  corrected_value  text,                  -- what the operator wanted
  lesson_learned   text        NOT NULL,  -- 1-2 sentence lesson for future reference
  entity_type      text,
  entity_id        uuid,
  entity_number    text,
  client_id        uuid        REFERENCES public.clients(id) ON DELETE SET NULL,
  operator_user_id uuid,
  scope            text        NOT NULL DEFAULT 'global'
                               CHECK (scope IN ('global', 'client', 'operator')),
  metadata         jsonb       NOT NULL DEFAULT '{}',
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_correction_patterns_client_idx
  ON public.ai_correction_patterns (client_id)
  WHERE client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ai_correction_patterns_type_idx
  ON public.ai_correction_patterns (correction_type, scope);

ALTER TABLE public.ai_correction_patterns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_corrections_read"
  ON public.ai_correction_patterns
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

CREATE POLICY "ai_corrections_insert"
  ON public.ai_correction_patterns
  FOR INSERT
  TO authenticated
  WITH CHECK (private.ai_op_is_active(auth.uid()));
