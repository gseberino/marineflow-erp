-- ai_inbound_sessions: tracks autonomous inbound WhatsApp conversation sessions.
-- Each active phone number gets one session (upserted on each message).
-- Stores recent message history for context + last detected intent.

CREATE TABLE IF NOT EXISTS public.ai_inbound_sessions (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         text        NOT NULL UNIQUE,
  client_id     uuid        REFERENCES public.clients(id) ON DELETE SET NULL,
  messages      jsonb       NOT NULL DEFAULT '[]',
  last_intent   text,
  session_data  jsonb       NOT NULL DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_inbound_sessions_client_idx
  ON public.ai_inbound_sessions (client_id)
  WHERE client_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.set_ai_inbound_sessions_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER ai_inbound_sessions_updated_at
  BEFORE UPDATE ON public.ai_inbound_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_ai_inbound_sessions_updated_at();

ALTER TABLE public.ai_inbound_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_inbound_sessions_read"
  ON public.ai_inbound_sessions
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));
