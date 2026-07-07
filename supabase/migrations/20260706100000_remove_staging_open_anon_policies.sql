-- Remove as políticas "staging_open_select/insert/update/delete" (roles
-- {anon,authenticated}, qual: true) que davam acesso total e irrestrito a
-- qualquer usuário anônimo em 60 tabelas — resquício de uma configuração
-- de staging que nunca foi removida. Todas as 60 tabelas já têm política
-- própria para o papel authenticated (confirmado via pg_policies antes
-- desta migration), então remover só as staging_open_* não afeta a equipe
-- logada, apenas fecha o acesso para quem não está.
--
-- Em seguida, cria políticas de leitura anônima ESCOPADAS apenas nas
-- tabelas que a página pública (PublicServiceOrderView.tsx, /view/:token)
-- realmente precisa, seguindo a mesma convenção já usada anteriormente em
-- anon_clients_via_share_token/anon_vessels_via_share_token (join até
-- service_orders.share_token IS NOT NULL).

DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'agenda_tasks','api_references','app_settings','app_users','audit_log',
    'bank_transactions','card_installment_fees','client_whatsapp_settings','clients',
    'collection_contacts','collection_templates','collections','commissions','cost_centers',
    'exchange_rates','external_quote_leads','external_quote_parts','external_quote_services',
    'external_quotes','financial_categories','fiscal_note_items','fiscal_notes','import_sessions',
    'inventory_movements','invoices','marinas','payables','payment_condition_presets','payments',
    'price_update_suggestions','product_categories','product_price_history','product_suppliers',
    'products','purchase_order_items','purchase_orders','push_subscriptions','receivables',
    'saved_filters','service_order_expenses','service_order_parts','service_order_photos',
    'service_order_services','service_order_signatures','service_order_technicians','service_orders',
    'services','supplier_product_mappings','suppliers','time_entries','vessel_contacts','vessels',
    'whatsapp_blocked_numbers','whatsapp_conversation_assignments','whatsapp_leads','whatsapp_messages',
    'whatsapp_quick_replies','whatsapp_read_state','whatsapp_scheduled_sends','whatsapp_send_queue',
    'whatsapp_status_scheduled','whatsapp_templates'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'staging_open_select', tbl);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'staging_open_insert', tbl);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'staging_open_update', tbl);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'staging_open_delete', tbl);
  END LOOP;
END $$;

-- Config pública da empresa (já usada até na tela de login, sem dado sensível de cliente)
DROP POLICY IF EXISTS anon_app_settings_select ON public.app_settings;
CREATE POLICY anon_app_settings_select ON public.app_settings
  FOR SELECT TO anon USING (true);

-- Rótulos/percentuais de condição de pagamento, não é dado sensível de cliente
DROP POLICY IF EXISTS anon_payment_condition_presets_select ON public.payment_condition_presets;
CREATE POLICY anon_payment_condition_presets_select ON public.payment_condition_presets
  FOR SELECT TO anon USING (true);

-- service_orders: só as que já têm link público gerado
DROP POLICY IF EXISTS anon_service_orders_via_share_token ON public.service_orders;
CREATE POLICY anon_service_orders_via_share_token ON public.service_orders
  FOR SELECT TO anon USING (share_token IS NOT NULL);

-- marinas: via join a service_orders com share_token
DROP POLICY IF EXISTS anon_marinas_via_share_token ON public.marinas;
CREATE POLICY anon_marinas_via_share_token ON public.marinas
  FOR SELECT TO anon USING (
    EXISTS (SELECT 1 FROM public.service_orders so WHERE so.marina_id = marinas.id AND so.share_token IS NOT NULL)
  );

-- service_order_parts: itens exibidos no link público
DROP POLICY IF EXISTS anon_service_order_parts_via_share_token ON public.service_order_parts;
CREATE POLICY anon_service_order_parts_via_share_token ON public.service_order_parts
  FOR SELECT TO anon USING (
    EXISTS (SELECT 1 FROM public.service_orders so WHERE so.id = service_order_parts.service_order_id AND so.share_token IS NOT NULL)
  );

-- service_order_services: itens exibidos no link público
DROP POLICY IF EXISTS anon_service_order_services_via_share_token ON public.service_order_services;
CREATE POLICY anon_service_order_services_via_share_token ON public.service_order_services
  FOR SELECT TO anon USING (
    EXISTS (SELECT 1 FROM public.service_orders so WHERE so.id = service_order_services.service_order_id AND so.share_token IS NOT NULL)
  );

-- service_order_signatures: para checar se já foi assinado no link público
-- (a gravação da assinatura é feita pelo edge function submit-signature via
-- service role, não precisa de política de INSERT para anon aqui)
DROP POLICY IF EXISTS anon_service_order_signatures_via_share_token ON public.service_order_signatures;
CREATE POLICY anon_service_order_signatures_via_share_token ON public.service_order_signatures
  FOR SELECT TO anon USING (
    EXISTS (SELECT 1 FROM public.service_orders so WHERE so.id = service_order_signatures.service_order_id AND so.share_token IS NOT NULL)
  );

-- products: para exibir nome/SKU das peças no link público (join de 2 níveis)
DROP POLICY IF EXISTS anon_products_via_share_token ON public.products;
CREATE POLICY anon_products_via_share_token ON public.products
  FOR SELECT TO anon USING (
    EXISTS (
      SELECT 1 FROM public.service_order_parts sp
      JOIN public.service_orders so ON so.id = sp.service_order_id
      WHERE sp.product_id = products.id AND so.share_token IS NOT NULL
    )
  );

-- clients/vessels já têm anon_clients_via_share_token/anon_vessels_via_share_token
-- de uma correção anterior — não precisam de política nova, só a remoção das
-- staging_open_* acima (feita no loop) já resolve a exposição nessas 2 tabelas.

-- Auditoria pós-migration encontrou MAIS 2 políticas totalmente abertas
-- (qual: true, sem escopo) sob nomes diferentes de "staging_open_*", que o
-- loop acima não pegou — substituídas pelas políticas escopadas criadas
-- logo acima nesta mesma migration.
DROP POLICY IF EXISTS "Public parts viewing via service order" ON public.service_order_parts;
DROP POLICY IF EXISTS "Public services viewing via service order" ON public.service_order_services;
