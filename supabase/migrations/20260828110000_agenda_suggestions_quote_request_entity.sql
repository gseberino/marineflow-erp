-- ─────────────────────────────────────────────────────────────────────────────
-- Alinha o CHECK de `agenda_suggestions.related_entity_type` ao de `agenda_tasks`.
--
-- Em 30/07/2026 a migration 20260730130000 ampliou a lista de `agenda_tasks` para
-- incluir 'quote_request' (a regra R17 gravava esse tipo, o INSERT falhava com 23514,
-- o catch por regra engolia e a regra ficava sem efeito com o cron reportando 200).
-- A tabela irmã ficou para trás: em 28/08/2026 o CHECK de `agenda_tasks` tinha 11
-- valores e o de `agenda_suggestions` ainda tinha os 10 originais.
--
-- Hoje o detector só grava service_order/client/null, então nada está quebrado — mas a
-- primeira sugestão que apontar para uma cotação a fornecedor cai no MESMO 23514, e o
-- insert de sugestão também engole erro diferente de 23505. Fechar agora custa uma
-- migration aditiva; fechar depois custa outra investigação de "por que não apareceu".
--
-- É aditivo: nenhuma linha existente viola a lista ampliada.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.agenda_suggestions
  drop constraint if exists agenda_suggestions_related_entity_type_check;

alter table public.agenda_suggestions
  add constraint agenda_suggestions_related_entity_type_check
  check (
    related_entity_type is null
    or related_entity_type = any (array[
      'service_order', 'quote', 'external_quote', 'client', 'vessel',
      'receivable', 'payable', 'purchase_order', 'collection', 'stock_item',
      -- novo: cotação a fornecedor (COT-), para não repetir o 23514 da R17
      'quote_request'
    ])
  );
