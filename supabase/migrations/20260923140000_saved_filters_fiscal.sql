-- Presets de filtro para a tela fiscal.
--
-- `saved_filters.filter_type` e uma lista FECHADA num CHECK. A tela de notas passou a
-- oferecer filtro com presets como o resto do sistema, e sem este ALTER o botao "salvar
-- filtro" subiria bonito e quebraria no primeiro clique -- a tela nao teria como saber
-- que o banco recusa o valor.
--
-- E a mesma armadilha ja registrada em agenda_tasks.related_entity_type: CHECK de lista
-- fechada nao avisa em tempo de compilacao, so na hora do insert.

alter table public.saved_filters
  drop constraint if exists saved_filters_filter_type_check;

alter table public.saved_filters
  add constraint saved_filters_filter_type_check
  check (filter_type = any (array[
    'payable', 'receivable', 'service_orders', 'quotes', 'products', 'vessels',
    'agenda', 'clients', 'suppliers', 'marinas', 'services', 'inventory',
    'purchase_orders', 'collections', 'crm', 'external_quotes',
    'whatsapp_leads', 'whatsapp_scheduled', 'whatsapp_logs',
    'fiscal_documents'
  ]));
