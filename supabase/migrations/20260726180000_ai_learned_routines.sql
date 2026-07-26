-- Agente que aprende (Fase 10-A): rotinas observadas do dia a dia.
-- O agente registra padrões que percebe ("toda segunda o dono cobra os atrasados"),
-- e essas rotinas viram sugestões de automação. Autonomia é CONQUISTADA com
-- evidência de repetição — nunca presumida (ver plans/marineflow-agenda-autonoma.md).
CREATE TABLE public.ai_learned_routines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- O que foi aprendido
  title text NOT NULL,                       -- "Cobrar inadimplentes toda segunda de manhã"
  pattern_key text NOT NULL,                 -- chave estável p/ dedupe: 'cobranca:semanal:segunda'
  description text,                          -- detalhes livres do padrão
  category text NOT NULL DEFAULT 'rotina'
    CHECK (category IN ('rotina','preferencia','contexto','atalho')),

  -- Evidência de repetição (o que justifica propor automação)
  observations integer NOT NULL DEFAULT 1,   -- quantas vezes foi observado
  last_observed_at timestamptz NOT NULL DEFAULT now(),
  evidence text,                             -- exemplo concreto da última observação

  -- Proposta de automação que essa rotina habilita
  suggested_automation text,                 -- "criar tarefa recorrente toda segunda 08:00"
  automation_payload jsonb,                  -- parâmetros prontos p/ executar quando aprovado

  -- Ciclo de vida da autonomia
  status text NOT NULL DEFAULT 'observed'
    CHECK (status IN ('observed','proposed','approved','rejected','automated')),
  approved_at timestamptz,
  approved_by uuid REFERENCES public.app_users(id),
  rejected_reason text,

  user_id uuid REFERENCES public.app_users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX ai_learned_routines_key ON public.ai_learned_routines (pattern_key, coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX ai_learned_routines_status ON public.ai_learned_routines (status, observations DESC);

ALTER TABLE public.ai_learned_routines ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_learned_routines_all ON public.ai_learned_routines
  FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
