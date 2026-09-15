-- O advisor de performance (15/09/2026) listava 159 chaves estrangeiras sem índice. Sem
-- índice no lado filho, cada leitura "tudo desta OS / deste produto / desta proposta" varre
-- a tabela inteira, e apagar um pai (cascade ou restrict) idem. O banco ainda é pequeno,
-- então hoje isso custa milissegundos — mas whatsapp_messages já passa de 6 mil linhas e
-- o extrato cresce todo dia. Índice em coluna de FK custa quase nada na escrita.
--
-- Critério: só as FKs que aparecem em JOIN/filtro de tela, RPC ou edge (caminho
-- filho→pai que alguém percorre). Colunas de auditoria (created_by, approved_by,
-- rejected_by...) ficam de fora de propósito: ninguém consulta "tudo que fulano aprovou"
-- e cada índice a mais é um custo por INSERT.

-- Conversas e extrato
create index if not exists idx_whatsapp_messages_service_order_id on public.whatsapp_messages (service_order_id);
create index if not exists idx_bank_transactions_reconciled_service_order_id on public.bank_transactions (reconciled_service_order_id);
create index if not exists idx_bank_transactions_reconciled_payment_id on public.bank_transactions (reconciled_payment_id);
create index if not exists idx_whatsapp_leads_linked_client_id on public.whatsapp_leads (linked_client_id);

-- Caixa de entrada financeira (o vigilante e o desfazer andam por estas colunas)
create index if not exists idx_finance_review_queue_related_transaction_id on public.finance_review_queue (related_transaction_id);
create index if not exists idx_finance_review_queue_created_payable_id on public.finance_review_queue (created_payable_id);
create index if not exists idx_finance_review_queue_created_receivable_id on public.finance_review_queue (created_receivable_id);
create index if not exists idx_finance_review_queue_applied_rule_id on public.finance_review_queue (applied_rule_id);
create index if not exists idx_finance_review_queue_suggested_supplier_id on public.finance_review_queue (suggested_supplier_id);
create index if not exists idx_finance_review_queue_suggested_client_id on public.finance_review_queue (suggested_client_id);
create index if not exists idx_finance_review_queue_suggested_payee_id on public.finance_review_queue (suggested_payee_id);
create index if not exists idx_finance_review_queue_suggested_service_order_id on public.finance_review_queue (suggested_service_order_id);
create index if not exists idx_reconciliation_log_payable_id on public.reconciliation_log (payable_id);
create index if not exists idx_reconciliation_log_receivable_id on public.reconciliation_log (receivable_id);

-- Contas, pagamentos, cobranças e fiscal
create index if not exists idx_payments_payable_id on public.payments (payable_id);
create index if not exists idx_payments_receivable_id on public.payments (receivable_id);
create index if not exists idx_collections_receivable_id on public.collections (receivable_id);
create index if not exists idx_payables_cost_center_id on public.payables (cost_center_id);
create index if not exists idx_receivables_invoice_id on public.receivables (invoice_id);
create index if not exists idx_issued_fiscal_documents_receivable_id on public.issued_fiscal_documents (receivable_id);
create index if not exists idx_commissions_payable_id on public.commissions (payable_id);
create index if not exists idx_commissions_user_id on public.commissions (user_id);
create index if not exists idx_payroll_lines_payable_id on public.payroll_lines (payable_id);
create index if not exists idx_payroll_lines_work_profile_id on public.payroll_lines (work_profile_id);

-- Ordem de serviço e o que pende dela
create index if not exists idx_service_order_parts_product_id on public.service_order_parts (product_id);
create index if not exists idx_service_order_services_service_order_id on public.service_order_services (service_order_id);
create index if not exists idx_service_order_services_service_id on public.service_order_services (service_id);
create index if not exists idx_service_order_steps_service_order_service_id on public.service_order_steps (service_order_service_id);
create index if not exists idx_service_order_steps_template_id on public.service_order_steps (template_id);
create index if not exists idx_service_order_expenses_service_order_id on public.service_order_expenses (service_order_id);
create index if not exists idx_service_order_expenses_linked_payable_id on public.service_order_expenses (linked_payable_id);
create index if not exists idx_service_order_expenses_supplier_id on public.service_order_expenses (supplier_id);
create index if not exists idx_service_order_photos_step_id on public.service_order_photos (step_id);
create index if not exists idx_service_order_technicians_user_id on public.service_order_technicians (user_id);
create index if not exists idx_service_orders_survey_id on public.service_orders (survey_id);
create index if not exists idx_service_orders_payment_condition_preset_id on public.service_orders (payment_condition_preset_id);
create index if not exists idx_service_orders_requested_by_contact_id on public.service_orders (requested_by_contact_id);
create index if not exists idx_ai_operator_sessions_service_order_id on public.ai_operator_sessions (service_order_id);
create index if not exists idx_time_entries_technician_user_id on public.time_entries (technician_user_id);

-- Levantamento
create index if not exists idx_service_surveys_service_id on public.service_surveys (service_id);
create index if not exists idx_service_surveys_client_id on public.service_surveys (client_id);
create index if not exists idx_service_surveys_vessel_id on public.service_surveys (vessel_id);
create index if not exists idx_service_survey_answers_template_id on public.service_survey_answers (template_id);
create index if not exists idx_survey_material_rules_product_id on public.survey_material_rules (product_id);

-- Catálogo, compras e entrada de mercadoria
create index if not exists idx_products_supplier_id on public.products (supplier_id);
create index if not exists idx_products_product_category_id on public.products (product_category_id);
create index if not exists idx_product_suppliers_supplier_id on public.product_suppliers (supplier_id);
create index if not exists idx_purchase_order_items_purchase_order_id on public.purchase_order_items (purchase_order_id);
create index if not exists idx_purchase_order_items_product_id on public.purchase_order_items (product_id);
create index if not exists idx_purchase_orders_service_order_id on public.purchase_orders (service_order_id);
create index if not exists idx_purchase_orders_supplier_id on public.purchase_orders (supplier_id);
create index if not exists idx_purchase_orders_payable_id on public.purchase_orders (payable_id);
create index if not exists idx_quote_request_items_service_order_service_id on public.quote_request_items (service_order_service_id);
create index if not exists idx_quote_request_items_service_order_part_id on public.quote_request_items (service_order_part_id);
create index if not exists idx_quote_request_items_product_id on public.quote_request_items (product_id);
create index if not exists idx_quote_request_sends_supplier_id on public.quote_request_sends (supplier_id);
create index if not exists idx_quote_responses_quote_request_item_id on public.quote_responses (quote_request_item_id);
create index if not exists idx_fiscal_note_items_product_id on public.fiscal_note_items (product_id);
create index if not exists idx_fiscal_notes_supplier_id on public.fiscal_notes (supplier_id);
create index if not exists idx_fiscal_notes_purchase_order_id on public.fiscal_notes (purchase_order_id);
create index if not exists idx_product_price_history_product_id on public.product_price_history (product_id);
create index if not exists idx_price_update_suggestions_product_id on public.price_update_suggestions (product_id);
create index if not exists idx_price_update_suggestions_fiscal_note_id on public.price_update_suggestions (fiscal_note_id);
create index if not exists idx_supplier_product_mappings_internal_product_id on public.supplier_product_mappings (internal_product_id);

-- Orçamento externo
create index if not exists idx_external_quotes_client_id on public.external_quotes (client_id);
create index if not exists idx_external_quotes_lead_id on public.external_quotes (lead_id);
create index if not exists idx_external_quotes_converted_service_order_id on public.external_quotes (converted_service_order_id);
create index if not exists idx_external_quote_parts_external_quote_id on public.external_quote_parts (external_quote_id);
create index if not exists idx_external_quote_services_external_quote_id on public.external_quote_services (external_quote_id);

-- Agenda, fios soltos e missões
create index if not exists idx_agenda_tasks_client_id on public.agenda_tasks (client_id);
create index if not exists idx_agenda_tasks_recurrence_parent_id on public.agenda_tasks (recurrence_parent_id);
create index if not exists idx_agenda_suggestions_client_id on public.agenda_suggestions (client_id);
create index if not exists idx_agenda_suggestions_created_task_id on public.agenda_suggestions (created_task_id);
create index if not exists idx_entity_open_loops_task_id on public.entity_open_loops (task_id);
create index if not exists idx_ai_followup_missions_service_order_id on public.ai_followup_missions (service_order_id);
create index if not exists idx_ai_followup_missions_open_loop_id on public.ai_followup_missions (open_loop_id);
create index if not exists idx_ai_followup_events_pending_action_id on public.ai_followup_events (pending_action_id);
create index if not exists idx_ai_operator_audit_pending_action_id on public.ai_operator_audit (pending_action_id);

insert into supabase_migrations.schema_migrations (version, name)
values ('20260915110000', 'indices_em_chaves_estrangeiras_quentes')
on conflict do nothing;
