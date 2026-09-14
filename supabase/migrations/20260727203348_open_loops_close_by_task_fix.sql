-- Recuperada do transcript da sessão (C--Users-PC/2d4124b3-a014-48da-8feb-73901aafa6ff.jsonl, 2026-07-27T20:33:43.539Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260727203348 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

ALTER TABLE public.agenda_suggestions
  ADD COLUMN IF NOT EXISTS open_loop_id uuid
    REFERENCES public.entity_open_loops(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS agenda_suggestions_open_loop
  ON public.agenda_suggestions (open_loop_id) WHERE open_loop_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.refresh_entity_open_loops()
RETURNS TABLE (abertos integer, fechados integer)
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_open integer := 0;
  v_closed integer := 0;
  v_n integer := 0;
BEGIN
  WITH ins AS (
    INSERT INTO entity_open_loops (
      entity_type, entity_id, loop_key, source, kind, title, detail,
      ref_table, ref_id, service_order_id, due_at, priority, last_seen_at
    )
    SELECT f.entity_type, f.entity_id, f.loop_key, 'erp', f.kind, f.title, f.detail,
           f.ref_table, f.ref_id, f.service_order_id, f.due_at, f.priority, now()
      FROM erp_open_loop_facts f
    ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
    DO UPDATE SET
      title            = EXCLUDED.title,
      detail           = EXCLUDED.detail,
      due_at           = EXCLUDED.due_at,
      priority         = EXCLUDED.priority,
      service_order_id = EXCLUDED.service_order_id,
      last_seen_at     = now(),
      updated_at       = now()
    RETURNING (xmax = 0) AS inserido
  )
  SELECT count(*) FILTER (WHERE inserido)::integer INTO v_open FROM ins;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'erp:fato encerrado', updated_at = now()
   WHERE l.source = 'erp' AND l.status = 'open'
     AND NOT EXISTS (
       SELECT 1 FROM erp_open_loop_facts f
        WHERE f.entity_type = l.entity_type AND f.entity_id = l.entity_id
          AND f.loop_key = l.loop_key);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_tasks t
   WHERE l.task_id = t.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('done', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_suggestions s
    JOIN agenda_tasks t ON t.id = s.created_task_id
   WHERE s.open_loop_id = l.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('done', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'OS encerrada', updated_at = now()
    FROM service_orders so
   WHERE l.service_order_id = so.id AND l.source = 'conversation' AND l.status = 'open'
     AND so.status IN ('completed', 'invoiced', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'expirado por inatividade', updated_at = now()
   WHERE l.source = 'conversation' AND l.status = 'open'
     AND l.last_seen_at < now() - interval '45 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  RETURN QUERY SELECT v_open, v_closed;
END;
$fn$;
