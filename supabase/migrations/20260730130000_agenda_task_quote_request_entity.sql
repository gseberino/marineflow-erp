-- ─────────────────────────────────────────────────────────────────────────────
-- Permite vincular tarefa da agenda a uma COTAÇÃO a fornecedor.
--
-- A regra R17 ("cobrar resposta da cotação") grava related_entity_type =
-- 'quote_request', mas o CHECK de agenda_tasks só conhecia os 10 tipos que
-- existiam quando a Agenda 2.0 foi construída. O INSERT falhava com 23514, o
-- motor capturava no catch por regra e seguia — a regra ficava silenciosamente
-- sem efeito, com o cron reportando sucesso.
--
-- É aditivo: nenhuma linha existente viola a lista ampliada.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.agenda_tasks
  drop constraint if exists agenda_tasks_related_entity_type_check;

alter table public.agenda_tasks
  add constraint agenda_tasks_related_entity_type_check
  check (
    related_entity_type is null
    or related_entity_type = any (array[
      'service_order', 'quote', 'external_quote', 'client', 'vessel',
      'receivable', 'payable', 'purchase_order', 'collection', 'stock_item',
      -- novo: cotação a fornecedor (COT-), usada pela regra R17
      'quote_request'
    ])
  );
