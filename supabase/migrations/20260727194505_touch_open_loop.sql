-- Recuperada do transcript da sessão (C--Users-PC/2d4124b3-a014-48da-8feb-73901aafa6ff.jsonl, 2026-07-27T19:45:01.251Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260727194505 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

CREATE OR REPLACE FUNCTION public.touch_open_loop(
  p_loop_id           uuid,
  p_evidence          text DEFAULT NULL,
  p_evidence_at       timestamptz DEFAULT NULL,
  p_source_message_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE sql VOLATILE
SET search_path = public
AS $fn$
  UPDATE entity_open_loops
     SET mentions          = mentions + 1,
         last_seen_at      = now(),
         evidence          = coalesce(p_evidence, evidence),
         evidence_at       = coalesce(p_evidence_at, evidence_at),
         source_message_id = coalesce(p_source_message_id, source_message_id),
         updated_at        = now()
   WHERE id = p_loop_id AND status = 'open'
  RETURNING mentions;
$fn$;
