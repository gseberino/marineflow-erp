-- Contexto Vivo — Fase 12: identidade dos contatos
-- Plano: plans/marineflow-contexto-vivo.md
--
-- Problema medido: 22 de 2.003 mensagens (1,1%) tinham cliente identificado. Sem saber
-- COM QUEM se fala, o agente não consegue agrupar assunto, vincular OS nem lembrar contexto.
--
-- Regra de casamento: ÚLTIMOS 8 DÍGITOS (mesma de _shared/ai/phone.ts) — o nono dígito e o
-- +55 variam entre o cadastro e o que o WhatsApp entrega; os 8 finais são estáveis.

-- Índices funcionais para o casamento ficar rápido (right(digits, 8))
CREATE INDEX IF NOT EXISTS clients_phone_key8
  ON public.clients (right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 8));
CREATE INDEX IF NOT EXISTS clients_whatsapp_key8
  ON public.clients (right(regexp_replace(coalesce(whatsapp, ''), '\D', '', 'g'), 8));
CREATE INDEX IF NOT EXISTS suppliers_phone_key8
  ON public.suppliers (right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 8));
CREATE INDEX IF NOT EXISTS leads_phone_key8
  ON public.external_quote_leads (right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 8));

/**
 * Resolve um telefone para a entidade dona dele.
 * Precedência: cliente > fornecedor > lead (cliente é o vínculo mais forte para o negócio).
 * Retorna no máximo uma linha; vazio quando não há casamento.
 */
CREATE OR REPLACE FUNCTION public.resolve_contact_identity(p_phone text)
RETURNS TABLE (kind text, entity_id uuid, entity_name text)
LANGUAGE sql STABLE
SET search_path = public
AS $$
  WITH k AS (
    SELECT right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 8) AS key8
  )
  SELECT x.kind, x.entity_id, x.entity_name FROM (
    SELECT 'client'::text, c.id, c.name, 1 AS prio
      FROM clients c, k
     WHERE length(k.key8) = 8
       AND (right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 8) = k.key8
         OR right(regexp_replace(coalesce(c.whatsapp, ''), '\D', '', 'g'), 8) = k.key8)
    UNION ALL
    SELECT 'supplier'::text, s.id, s.name, 2
      FROM suppliers s, k
     WHERE length(k.key8) = 8
       AND right(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g'), 8) = k.key8
    UNION ALL
    SELECT 'lead'::text, l.id, l.name, 3
      FROM external_quote_leads l, k
     WHERE length(k.key8) = 8
       AND (right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) = k.key8
         OR right(regexp_replace(coalesce(l.whatsapp, ''), '\D', '', 'g'), 8) = k.key8)
  ) x(kind, entity_id, entity_name, prio)
  ORDER BY x.prio
  LIMIT 1;
$$;

/**
 * Preenche client_id/supplier_id/lead_id nas mensagens que ainda não têm vínculo.
 * Idempotente e incremental (p_limit por execução). Devolve quantas foram ligadas.
 */
CREATE OR REPLACE FUNCTION public.backfill_message_identity(p_limit integer DEFAULT 2000)
RETURNS TABLE (linked_clients integer, linked_suppliers integer, linked_leads integer)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_clients integer := 0;
  v_suppliers integer := 0;
  v_leads integer := 0;
BEGIN
  WITH alvo AS (
    SELECT m.id, m.phone_normalized
      FROM whatsapp_messages m
     WHERE m.client_id IS NULL AND m.supplier_id IS NULL AND m.lead_id IS NULL
       AND m.phone_normalized IS NOT NULL
     ORDER BY m.occurred_at DESC
     LIMIT p_limit
  ), res AS (
    SELECT a.id, r.kind, r.entity_id
      FROM alvo a
      CROSS JOIN LATERAL public.resolve_contact_identity(a.phone_normalized) r
  ), upd AS (
    UPDATE whatsapp_messages m
       SET client_id   = CASE WHEN res.kind = 'client'   THEN res.entity_id ELSE m.client_id END,
           supplier_id = CASE WHEN res.kind = 'supplier' THEN res.entity_id ELSE m.supplier_id END,
           lead_id     = CASE WHEN res.kind = 'lead'     THEN res.entity_id ELSE m.lead_id END
      FROM res
     WHERE m.id = res.id
    RETURNING res.kind
  )
  SELECT
    count(*) FILTER (WHERE kind = 'client')::integer,
    count(*) FILTER (WHERE kind = 'supplier')::integer,
    count(*) FILTER (WHERE kind = 'lead')::integer
    INTO v_clients, v_suppliers, v_leads
  FROM upd;

  RETURN QUERY SELECT v_clients, v_suppliers, v_leads;
END;
$$;

-- Contatos ainda não identificados, ordenados por relevância (quem mais fala primeiro).
-- Alimenta a fila "quem é este contato?" — o agente pergunta UMA vez e resolve para sempre.
CREATE OR REPLACE VIEW public.unidentified_contacts AS
SELECT
  m.phone_normalized,
  count(*)                              AS mensagens,
  max(m.occurred_at)                    AS ultima_mensagem,
  (array_agg(m.body ORDER BY m.occurred_at DESC)
     FILTER (WHERE m.body IS NOT NULL AND m.body <> ''))[1] AS ultima_frase
FROM whatsapp_messages m
WHERE m.client_id IS NULL AND m.supplier_id IS NULL AND m.lead_id IS NULL
  AND m.phone_normalized IS NOT NULL
  AND m.occurred_at > now() - interval '90 days'
GROUP BY m.phone_normalized
HAVING count(*) >= 2
ORDER BY count(*) DESC;
