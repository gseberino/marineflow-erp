-- Contexto Vivo — Fase 13: fios soltos por entidade ("open loops")
-- Plano: plans/marineflow-contexto-vivo.md
--
-- O que é: a resposta a "o que está em aberto com este cliente AGORA?".
-- Duas fontes alimentam a mesma tabela:
--   1. ERP    — fato duro (OS ativa, orçamento aguardando, título a vencer, compra a receber).
--              Recalculado a cada 15 min; some sozinho quando o ERP prova que acabou.
--   2. CONVERSA — o que foi prometido/pedido no WhatsApp e ainda não virou fato no ERP.
--              Sempre com a frase literal que o originou (mesma disciplina anti-alucinação
--              da caixa de entrada).
--
-- Regra de precedência do plano: fato do ERP manda. Se o banco diz que a OS fechou,
-- não importa o que a conversa sugeria — o fio fecha.
--
-- Zero IA aqui: tudo é SQL determinístico, roda dentro do motor de 15 min.

CREATE TABLE IF NOT EXISTS public.entity_open_loops (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type       text NOT NULL CHECK (entity_type IN ('client', 'supplier')),
  entity_id         uuid NOT NULL,
  -- Chave estável do fio. Para o ERP é derivada da linha de origem ('so:<uuid>'), o que
  -- torna o recálculo idempotente. Para conversa é um slug do assunto.
  loop_key          text NOT NULL,
  source            text NOT NULL CHECK (source IN ('erp', 'conversation')),
  kind              text NOT NULL,
  title             text NOT NULL,
  detail            text,
  ref_table         text,
  ref_id            uuid,
  service_order_id  uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  due_at            timestamptz,
  priority          text NOT NULL DEFAULT 'normal'
                      CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  status            text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  -- Rastro da conversa (só para source='conversation')
  evidence          text,
  evidence_at       timestamptz,
  source_message_id uuid,
  task_id           uuid REFERENCES public.agenda_tasks(id) ON DELETE SET NULL,
  -- Quantas vezes o assunto reapareceu. É isto que substitui a duplicação: a segunda
  -- menção incrementa o contador em vez de criar um fio novo.
  mentions          integer NOT NULL DEFAULT 1,
  opened_at         timestamptz NOT NULL DEFAULT now(),
  last_seen_at      timestamptz NOT NULL DEFAULT now(),
  resolved_at       timestamptz,
  resolved_reason   text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- Um único fio vivo por assunto e entidade. Parcial: fios resolvidos podem repetir a chave
-- (o mesmo assunto pode reabrir meses depois sem colidir com o histórico).
CREATE UNIQUE INDEX IF NOT EXISTS entity_open_loops_alive
  ON public.entity_open_loops (entity_type, entity_id, loop_key)
  WHERE status = 'open';

CREATE INDEX IF NOT EXISTS entity_open_loops_entity
  ON public.entity_open_loops (entity_type, entity_id, status, due_at NULLS LAST);
CREATE INDEX IF NOT EXISTS entity_open_loops_so
  ON public.entity_open_loops (service_order_id) WHERE service_order_id IS NOT NULL;

ALTER TABLE public.entity_open_loops ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_open_loops_all ON public.entity_open_loops
  FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

/**
 * Fatos do ERP que constituem fio solto AGORA.
 * É a fonte da verdade do recálculo: o que está aqui deve existir como fio aberto;
 * o que saiu daqui deve fechar. Deixar como view (e não embutir na função) permite
 * inspecionar "por que este fio existe?" com um SELECT.
 */
CREATE OR REPLACE VIEW public.erp_open_loop_facts AS
-- 1. Ordem de serviço em andamento
SELECT
  'client'::text AS entity_type,
  so.client_id   AS entity_id,
  'so:' || so.id::text AS loop_key,
  'service_order'::text AS kind,
  ('OS ' || so.service_order_number || ' — ' || CASE so.status
      WHEN 'open'           THEN 'aberta'
      WHEN 'approved'       THEN 'aprovada, a agendar'
      WHEN 'scheduled'      THEN 'agendada'
      WHEN 'in_progress'    THEN 'em execução'
      WHEN 'awaiting_parts' THEN 'aguardando peças'
      ELSE so.status END)::text AS title,
  left(coalesce(so.problem_description, ''), 180)::text AS detail,
  'service_orders'::text AS ref_table,
  so.id AS ref_id,
  so.id AS service_order_id,
  so.scheduled_start_at AS due_at,
  (CASE WHEN so.status = 'awaiting_parts' THEN 'high' ELSE 'normal' END)::text AS priority
FROM public.service_orders so
WHERE so.client_id IS NOT NULL
  AND so.status IN ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts')

UNION ALL

-- 2. Materiais de uma OS ainda não recebidos — AGREGADO por OS, não por item.
--    É este fato que permite dizer "entrega dos materiais da OS-1042" em vez de "baterias".
SELECT
  'client'::text,
  so.client_id,
  'so-parts:' || so.id::text,
  'delivery'::text,
  ('Materiais da OS ' || so.service_order_number || ' a receber')::text,
  (count(DISTINCT poi.id)::text || ' item(ns) pendente(s): ' ||
   left(string_agg(DISTINCT coalesce(poi.description, 'item'), ', '), 150))::text,
  'purchase_orders'::text,
  -- não há min(uuid) no Postgres: pega a compra mais antiga a chegar como referência
  (array_agg(po.id ORDER BY po.expected_date NULLS LAST, po.id))[1],
  so.id,
  min((po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo')),
  (CASE WHEN min(po.expected_date) < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
JOIN public.service_orders so ON so.id = po.service_order_id
JOIN public.purchase_order_items poi ON poi.purchase_order_id = po.id
WHERE so.client_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')
  AND coalesce(poi.received_qty, 0) < poi.quantity
GROUP BY so.id, so.client_id, so.service_order_number

UNION ALL

-- 3. Orçamento aguardando decisão do cliente
SELECT
  'client'::text,
  q.client_id,
  'quote:' || q.id::text,
  'quote'::text,
  ('Orçamento ' || coalesce(q.quote_number, '') || ' aguardando resposta do cliente')::text,
  left(coalesce(q.problem_description, ''), 180)::text,
  'external_quotes'::text,
  q.id,
  NULL::uuid,
  (q.quote_validity_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  'normal'::text
FROM public.external_quotes q
WHERE q.client_id IS NOT NULL
  AND q.status IN ('pending_approval', 'pending_product')

UNION ALL

-- 4. Título a receber vencido ou vencendo. Recorte de 15 dias de propósito: um boleto para
--    daqui a 3 meses não é fio solto, é agenda — poluiria o painel sem pedir ação.
SELECT
  'client'::text,
  r.client_id,
  'ar:' || r.id::text,
  'receivable'::text,
  ((CASE WHEN r.due_date < current_date THEN 'Título VENCIDO ' ELSE 'Título a vencer ' END)
   -- translate(',.' → '.,') porque to_char devolve separador no padrão do servidor (1,710.00)
   -- e o valor é lido por humano em pt-BR (1.710,00).
   || 'R$ ' || translate(to_char(coalesce(r.balance_amount, r.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(r.description, ''), 180)::text,
  'receivables'::text,
  r.id,
  r.service_order_id,
  (r.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN r.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.receivables r
WHERE r.client_id IS NOT NULL
  AND r.status = 'pending'
  AND r.due_date <= current_date + 15
  -- título quitado que ficou com status 'pending' não é fio solto, é sujeira de cadastro
  AND coalesce(r.balance_amount, r.amount) > 0

UNION ALL

-- 5. Compra pendente no fornecedor (lado do fornecedor)
SELECT
  'supplier'::text,
  po.supplier_id,
  'po:' || po.id::text,
  'purchase_order'::text,
  ('Compra ' || coalesce(po.po_number, '') || ' aguardando entrega')::text,
  left(coalesce(po.notes, ''), 180)::text,
  'purchase_orders'::text,
  po.id,
  po.service_order_id,
  (po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN po.expected_date < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
WHERE po.supplier_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')

UNION ALL

-- 6. Título a pagar vencido ou vencendo (lado do fornecedor)
SELECT
  'supplier'::text,
  p.supplier_id,
  'ap:' || p.id::text,
  'payable'::text,
  ((CASE WHEN p.due_date < current_date THEN 'Pagamento VENCIDO ' ELSE 'Pagamento a vencer ' END)
   || 'R$ ' || translate(to_char(coalesce(p.balance_amount, p.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(p.description, ''), 180)::text,
  'payables'::text,
  p.id,
  p.linked_service_order_id,
  (p.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN p.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.payables p
WHERE p.supplier_id IS NOT NULL
  AND p.status = 'pending'
  AND p.due_date <= current_date + 15
  AND coalesce(p.balance_amount, p.amount) > 0;

/**
 * Reconcilia os fios soltos com a realidade do ERP. Idempotente — pode rodar a cada 15 min.
 *
 * 1. Fatos do ERP viram fios (abre novo ou atualiza o existente).
 * 2. Fio de ERP cujo fato sumiu → resolvido (a OS fechou, o título foi pago, a compra chegou).
 * 3. Fio de conversa cuja tarefa foi concluída, ou cuja OS fechou → resolvido.
 * 4. Fio de conversa esquecido há mais de 45 dias → resolvido como expirado, para o painel
 *    não virar um cemitério de promessas antigas.
 */
CREATE OR REPLACE FUNCTION public.refresh_entity_open_loops()
RETURNS TABLE (abertos integer, fechados integer)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_open integer := 0;
  v_closed integer := 0;
  v_n integer := 0;
BEGIN
  -- 1 e 2: sincroniza os fios de origem ERP
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

  -- 3: fio de conversa que a tarefa vinculada já resolveu
  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'tarefa concluída', updated_at = now()
    FROM agenda_tasks t
   WHERE l.task_id = t.id AND l.source = 'conversation' AND l.status = 'open'
     AND t.status IN ('completed', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  -- 3b: fio de conversa preso a uma OS que já encerrou (precedência do ERP)
  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'OS encerrada', updated_at = now()
    FROM service_orders so
   WHERE l.service_order_id = so.id AND l.source = 'conversation' AND l.status = 'open'
     AND so.status IN ('completed', 'invoiced', 'cancelled');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  -- 4: expiração por silêncio
  UPDATE entity_open_loops l
     SET status = 'resolved', resolved_at = now(),
         resolved_reason = 'expirado por inatividade', updated_at = now()
   WHERE l.source = 'conversation' AND l.status = 'open'
     AND l.last_seen_at < now() - interval '45 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  RETURN QUERY SELECT v_open, v_closed;
END;
$$;

/**
 * Registra (ou reforça) um fio solto vindo da conversa.
 * Menção repetida do MESMO assunto NÃO cria fio novo: incrementa mentions e atualiza a
 * evidência — é o mecanismo que impede a segunda sugestão quase-igual.
 * Devolve o id do fio e se ele acabou de nascer.
 */
CREATE OR REPLACE FUNCTION public.record_conversation_loop(
  p_entity_type       text,
  p_entity_id         uuid,
  p_loop_key          text,
  p_kind              text,
  p_title             text,
  p_detail            text DEFAULT NULL,
  p_service_order_id  uuid DEFAULT NULL,
  p_due_at            timestamptz DEFAULT NULL,
  p_priority          text DEFAULT 'normal',
  p_evidence          text DEFAULT NULL,
  p_evidence_at       timestamptz DEFAULT NULL,
  p_source_message_id uuid DEFAULT NULL
)
RETURNS TABLE (loop_id uuid, criado boolean)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_new boolean;
BEGIN
  INSERT INTO entity_open_loops (
    entity_type, entity_id, loop_key, source, kind, title, detail,
    service_order_id, due_at, priority, evidence, evidence_at, source_message_id, last_seen_at
  )
  VALUES (
    p_entity_type, p_entity_id, p_loop_key, 'conversation', p_kind, p_title, p_detail,
    p_service_order_id, p_due_at, coalesce(p_priority, 'normal'),
    p_evidence, p_evidence_at, p_source_message_id, now()
  )
  ON CONFLICT (entity_type, entity_id, loop_key) WHERE status = 'open'
  DO UPDATE SET
    mentions          = entity_open_loops.mentions + 1,
    last_seen_at      = now(),
    -- A evidência mais recente vale mais que a primeira: é o estado atual do assunto.
    evidence          = coalesce(EXCLUDED.evidence, entity_open_loops.evidence),
    evidence_at       = coalesce(EXCLUDED.evidence_at, entity_open_loops.evidence_at),
    source_message_id = coalesce(EXCLUDED.source_message_id, entity_open_loops.source_message_id),
    due_at            = coalesce(EXCLUDED.due_at, entity_open_loops.due_at),
    service_order_id  = coalesce(EXCLUDED.service_order_id, entity_open_loops.service_order_id),
    updated_at        = now()
  RETURNING id, (xmax = 0) INTO v_id, v_new;

  RETURN QUERY SELECT v_id, v_new;
END;
$$;

/**
 * Reforça um fio existente: o assunto foi cobrado de novo.
 * Incremento feito no banco (e não com leitura-antes-de-escrita na edge function) para não
 * perder menções quando duas conversas tocam o mesmo fio na mesma execução.
 * Serve para fio de ERP também — anexar a frase do cliente a uma OS aberta é justamente o
 * que dá contexto de conversa a um fato do sistema.
 */
CREATE OR REPLACE FUNCTION public.touch_open_loop(
  p_loop_id           uuid,
  p_evidence          text DEFAULT NULL,
  p_evidence_at       timestamptz DEFAULT NULL,
  p_source_message_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE sql VOLATILE
SET search_path = public
AS $$
  UPDATE entity_open_loops
     SET mentions          = mentions + 1,
         last_seen_at      = now(),
         evidence          = coalesce(p_evidence, evidence),
         evidence_at       = coalesce(p_evidence_at, evidence_at),
         source_message_id = coalesce(p_source_message_id, source_message_id),
         updated_at        = now()
   WHERE id = p_loop_id AND status = 'open'
  RETURNING mentions;
$$;

/**
 * O que está em aberto com esta entidade, na ordem em que pede atenção.
 * Alimenta tanto o painel da tela do cliente quanto a tool do agente.
 */
CREATE OR REPLACE FUNCTION public.get_entity_open_loops(
  p_entity_type text,
  p_entity_id   uuid,
  p_limit       integer DEFAULT 20
)
RETURNS TABLE (
  id uuid, kind text, source text, title text, detail text,
  due_at timestamptz, priority text, service_order_id uuid,
  service_order_number text, mentions integer, evidence text,
  opened_at timestamptz, last_seen_at timestamptz, atrasado boolean
)
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT l.id, l.kind, l.source, l.title, l.detail, l.due_at, l.priority,
         l.service_order_id, so.service_order_number, l.mentions, l.evidence,
         l.opened_at, l.last_seen_at,
         (l.due_at IS NOT NULL AND l.due_at < now()) AS atrasado
    FROM entity_open_loops l
    LEFT JOIN service_orders so ON so.id = l.service_order_id
   WHERE l.entity_type = p_entity_type
     AND l.entity_id = p_entity_id
     AND l.status = 'open'
   ORDER BY
     (l.due_at IS NOT NULL AND l.due_at < now()) DESC,
     CASE l.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
     l.due_at NULLS LAST,
     l.last_seen_at DESC
   LIMIT coalesce(p_limit, 20);
$$;

-- Primeira carga: popula os fios de ERP com o estado atual.
SELECT public.refresh_entity_open_loops();
