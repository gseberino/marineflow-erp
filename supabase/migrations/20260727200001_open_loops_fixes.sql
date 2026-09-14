-- Correções encontradas na revisão da Fase 13/14 (27/07/2026).
-- Três defeitos, dois deles silenciosos:

-- ------------------------------------------------------------------------------------
-- 1. SEGURANÇA — view rodando com privilégio do dono, não de quem chama.
--
-- No Postgres, uma view executa por padrão com os privilégios do DONO (postgres), então a
-- RLS das tabelas base é ignorada. Medido com SET ROLE anon: o papel ANÔNIMO lia 23 fios do
-- ERP (com valores de títulos vencidos) e 95 contatos não identificados (telefone + trecho
-- da última mensagem). security_invoker faz a view respeitar a RLS de quem consulta; o
-- REVOKE é a segunda camada.
-- ------------------------------------------------------------------------------------
ALTER VIEW public.erp_open_loop_facts   SET (security_invoker = on);
ALTER VIEW public.unidentified_contacts SET (security_invoker = on);

REVOKE ALL ON public.erp_open_loop_facts   FROM anon;
REVOKE ALL ON public.unidentified_contacts FROM anon;

REVOKE EXECUTE ON FUNCTION public.refresh_entity_open_loops()                   FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_open_loop(uuid, text, timestamptz, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_conversation_loop(
  text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid
) FROM anon;
REVOKE EXECUTE ON FUNCTION public.backfill_message_identity(integer)            FROM anon;

-- ------------------------------------------------------------------------------------
-- 2. O fio nunca fechava por tarefa concluída — a razão mais natural de fechar.
--
-- Dois erros somados: (a) NADA gravava entity_open_loops.task_id, e (b) a regra procurava
-- status 'completed', mas agenda_tasks usa 'done'. Ou seja, o caminho era código morto duas
-- vezes. Um fio de conversa só fechava por OS encerrada ou pelos 45 dias de inatividade.
--
-- A ligação vai pela SUGESTÃO, não só pela tarefa: assim funciona tanto quando o detector
-- cria a tarefa sozinho quanto quando VOCÊ aceita o card na caixa de entrada (o fluxo de
-- aceite já preenche created_task_id) — sem precisar mudar o frontend.
-- ------------------------------------------------------------------------------------
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

  -- (a) fio ligado diretamente a uma tarefa (caminho da autonomia)
  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_tasks t
   WHERE l.task_id = t.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('done', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  -- (b) fio ligado pela sugestão que VOCÊ aceitou na caixa de entrada
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
