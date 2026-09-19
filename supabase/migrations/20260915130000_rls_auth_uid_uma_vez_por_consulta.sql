-- auth_rls_initplan (advisor de performance, 15/09/2026): 229 policies em 128 tabelas chamam
-- auth.uid()/auth.role()/auth.jwt() POR LINHA. Envolver em (select ...) faz o Postgres avaliar
-- uma vez por consulta (InitPlan) e o resultado da policy nao muda em nada: e a mesma
-- expressao, com o mesmo valor, decidida uma vez em vez de N.
--
-- Gerado a partir de pg_policy da producao (pg_get_expr de USING e WITH CHECK, com
-- regexp_replace de auth.<fn>() por (select auth.<fn>())). ALTER POLICY so troca USING/
-- WITH CHECK: comando, papeis (TO ...) e permissive/restrictive ficam como estao.
--
-- O teste estatico src/test/rls-financeiro-tecnico.test.ts nao interpreta ALTER POLICY;
-- ele continua julgando o CREATE POLICY original, cuja barreira e a mesma.

alter policy agenda_detector_exclusions_all on public.agenda_detector_exclusions using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy agenda_suggestions_select on public.agenda_suggestions using ((((select auth.uid()) IS NOT NULL) AND ((target_user_id IS NULL) OR (target_user_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = (select auth.uid())) AND (u.role = 'admin'::text) AND u.active))))));
alter policy agenda_suggestions_update on public.agenda_suggestions using ((((select auth.uid()) IS NOT NULL) AND ((target_user_id IS NULL) OR (target_user_id = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = (select auth.uid())) AND (u.role = 'admin'::text) AND u.active)))))) with check (((select auth.uid()) IS NOT NULL));
alter policy agenda_tasks_delete on public.agenda_tasks using ((((select auth.uid()) IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = (select auth.uid())) OR (created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = (select auth.uid())) AND (u.role = 'admin'::text) AND u.active))))));
alter policy agenda_tasks_insert on public.agenda_tasks with check (((select auth.uid()) IS NOT NULL));
alter policy agenda_tasks_select on public.agenda_tasks using ((((select auth.uid()) IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = (select auth.uid())) OR (created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = (select auth.uid())) AND (u.role = 'admin'::text) AND u.active))))));
alter policy agenda_tasks_update on public.agenda_tasks using ((((select auth.uid()) IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = (select auth.uid())) OR (created_by = (select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = (select auth.uid())) AND (u.role = 'admin'::text) AND u.active)))))) with check (((select auth.uid()) IS NOT NULL));
alter policy ai_memory_read on public.ai_agent_memory using (private.ai_op_is_active((select auth.uid())));
alter policy ai_agent_tasks_read on public.ai_agent_tasks using (private.ai_op_is_active((select auth.uid())));
alter policy ai_alerts_read on public.ai_business_alerts using (private.ai_op_is_active((select auth.uid())));
alter policy authenticated_all_ai_comms_log on public.ai_comms_log using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy ai_corrections_insert on public.ai_correction_patterns with check (private.ai_op_is_active((select auth.uid())));
alter policy ai_corrections_read on public.ai_correction_patterns using (private.ai_op_is_active((select auth.uid())));
alter policy ai_briefings_read on public.ai_daily_briefings using (private.ai_op_is_active((select auth.uid())));
alter policy followup_events_insert on public.ai_followup_events with check ((NOT is_external_seller((select auth.uid()))));
alter policy followup_events_select on public.ai_followup_events using ((NOT is_external_seller((select auth.uid()))));
alter policy followup_missions_insert on public.ai_followup_missions with check ((NOT is_external_seller((select auth.uid()))));
alter policy followup_missions_select on public.ai_followup_missions using ((NOT is_external_seller((select auth.uid()))));
alter policy followup_missions_update on public.ai_followup_missions using ((NOT is_external_seller((select auth.uid())))) with check ((NOT is_external_seller((select auth.uid()))));
alter policy ai_inbound_sessions_read on public.ai_inbound_sessions using (private.ai_op_is_active((select auth.uid())));
alter policy ai_learned_routines_all on public.ai_learned_routines using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy ai_lifecycle_events_read on public.ai_lifecycle_events using (private.ai_op_is_active((select auth.uid())));
alter policy authenticated_all_ai_message_feedback on public.ai_message_feedback using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy ai_op_audit_select on public.ai_operator_audit using (private.ai_op_is_admin_or_financial((select auth.uid())));
alter policy ai_op_channel_events_select on public.ai_operator_channel_events using (private.ai_op_is_admin((select auth.uid())));
alter policy ai_op_draft_items_select on public.ai_operator_draft_items using ((private.ai_op_is_active((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM ai_operator_drafts d
  WHERE ((d.id = ai_operator_draft_items.draft_id) AND ((d.created_by = (select auth.uid())) OR private.ai_op_is_admin((select auth.uid())) OR (EXISTS ( SELECT 1
           FROM ai_operator_sessions s
          WHERE ((s.id = d.session_id) AND (s.owner_user_id = (select auth.uid())))))))))));
alter policy ai_op_drafts_select on public.ai_operator_drafts using ((private.ai_op_is_active((select auth.uid())) AND ((created_by = (select auth.uid())) OR private.ai_op_is_admin((select auth.uid())) OR (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_drafts.session_id) AND (s.owner_user_id = (select auth.uid()))))))));
alter policy ai_op_memory_select on public.ai_operator_memory_notes using ((private.ai_op_is_active((select auth.uid())) AND (((verification_status = 'verified'::text) AND private.ai_op_is_internal((select auth.uid()))) OR ((verification_status = ANY (ARRAY['candidate'::text, 'rejected'::text])) AND (private.ai_op_is_admin((select auth.uid())) OR (EXISTS ( SELECT 1
   FROM app_users au
  WHERE ((au.id = (select auth.uid())) AND (au.active = true) AND (au.role = 'technician'::text)))) OR (created_by = (select auth.uid())))))));
alter policy ai_op_messages_select on public.ai_operator_messages using ((private.ai_op_is_active((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_messages.session_id) AND ((s.owner_user_id = (select auth.uid())) OR private.ai_op_is_admin((select auth.uid()))))))));
alter policy ai_op_pending_select on public.ai_operator_pending_actions using ((private.ai_op_is_active((select auth.uid())) AND ((requested_by_user_id = (select auth.uid())) OR private.ai_op_is_admin((select auth.uid())) OR (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_pending_actions.session_id) AND (s.owner_user_id = (select auth.uid()))))))));
alter policy ai_op_sessions_select on public.ai_operator_sessions using ((private.ai_op_is_active((select auth.uid())) AND ((owner_user_id = (select auth.uid())) OR private.ai_op_is_admin((select auth.uid())))));
alter policy ai_suggestion_reviews_all on public.ai_suggestion_reviews using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy ai_workflows_read on public.ai_workflows using (private.ai_op_is_active((select auth.uid())));
alter policy ai_workflows_write on public.ai_workflows using (private.ai_op_is_active((select auth.uid()))) with check (private.ai_op_is_active((select auth.uid())));
alter policy api_references_read_auth on public.api_references using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy app_error_logs_admin_select on public.app_error_logs using (is_admin((select auth.uid())));
alter policy app_error_logs_admin_update on public.app_error_logs using (is_admin((select auth.uid())));
alter policy app_notifications_select on public.app_notifications using ((user_id = (select auth.uid())));
alter policy app_notifications_update on public.app_notifications using ((user_id = (select auth.uid()))) with check ((user_id = (select auth.uid())));
alter policy app_settings_auth_delete on public.app_settings using ((is_admin_or_financial((select auth.uid())) AND (key <> 'cron_worker_secret'::text)));
alter policy app_settings_auth_insert on public.app_settings with check ((is_admin_or_financial((select auth.uid())) AND (key <> 'cron_worker_secret'::text)));
alter policy app_settings_auth_update on public.app_settings using ((is_admin_or_financial((select auth.uid())) AND (key <> 'cron_worker_secret'::text))) with check ((is_admin_or_financial((select auth.uid())) AND (key <> 'cron_worker_secret'::text)));
alter policy app_users_delete_admin_only on public.app_users using (is_admin((select auth.uid())));
alter policy app_users_insert_admin_only on public.app_users with check (is_admin((select auth.uid())));
alter policy app_users_select_self_or_admin on public.app_users using ((((select auth.uid()) = id) OR is_admin((select auth.uid()))));
alter policy app_users_update_admin_only on public.app_users using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy audit_log_insert_auth on public.audit_log with check (((select auth.uid()) IS NOT NULL));
alter policy audit_log_select_auth on public.audit_log using (((select auth.uid()) IS NOT NULL));
alter policy "financeiro le conferencias de saldo" on public.bank_balance_checks using (is_admin_or_financial((select auth.uid())));
alter policy bank_charges_select on public.bank_charges using (((select auth.uid()) IS NOT NULL));
alter policy bank_charges_write on public.bank_charges using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy bank_connections_select on public.bank_connections using (((select auth.uid()) IS NOT NULL));
alter policy bank_connections_write on public.bank_connections using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy bank_transactions_delete on public.bank_transactions using (is_admin_or_financial((select auth.uid())));
alter policy bank_transactions_insert on public.bank_transactions with check (is_admin_or_financial((select auth.uid())));
alter policy bank_transactions_select on public.bank_transactions using (is_admin_or_financial((select auth.uid())));
alter policy bank_transactions_update on public.bank_transactions using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy card_fees_delete_admin_financial on public.card_installment_fees using (is_admin_or_financial((select auth.uid())));
alter policy card_fees_read_authenticated on public.card_installment_fees using (((select auth.uid()) IS NOT NULL));
alter policy card_fees_update_admin_financial on public.card_installment_fees using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy card_fees_write_admin_financial on public.card_installment_fees with check (is_admin_or_financial((select auth.uid())));
alter policy client_whatsapp_settings_all_auth on public.client_whatsapp_settings using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_clients on public.clients using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_full_access on public.collection_contacts using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_full_access on public.collection_templates using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_full_access on public.collections using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Admins can do everything on commissions" on public.commissions using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy "Users can view own commissions" on public.commissions using (((select auth.uid()) = user_id));
alter policy commissions_admin_all on public.commissions using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy commissions_self_select on public.commissions using (((select auth.uid()) = user_id));
alter policy cfs_insert on public.company_fiscal_settings with check (is_admin((select auth.uid())));
alter policy cfs_select on public.company_fiscal_settings using (is_admin((select auth.uid())));
alter policy cfs_update on public.company_fiscal_settings using (is_admin((select auth.uid())));
alter policy "Enable read/write for all authenticated users" on public.cost_centers using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy cost_centers_all_authenticated on public.cost_centers using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy dc_amp_write on public.dc_ampacity_ratings using ((NOT is_external_seller((select auth.uid())))) with check ((NOT is_external_seller((select auth.uid()))));
alter policy entity_open_loops_all on public.entity_open_loops using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_exchange_rates on public.exchange_rates using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy eql_delete on public.external_quote_leads using (is_admin_or_financial((select auth.uid())));
alter policy eql_insert on public.external_quote_leads with check ((created_by = (select auth.uid())));
alter policy eql_select on public.external_quote_leads using (((created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid()))));
alter policy eql_update on public.external_quote_leads using (((created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid())))) with check (((created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid()))));
alter policy eqp_all on public.external_quote_parts using ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_parts.external_quote_id) AND ((q.created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_parts.external_quote_id) AND ((q.created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid())))))));
alter policy eqs_all on public.external_quote_services using ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_services.external_quote_id) AND ((q.created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_services.external_quote_id) AND ((q.created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid())))))));
alter policy eq_delete on public.external_quotes using ((is_admin_or_financial((select auth.uid())) OR ((created_by = (select auth.uid())) AND (status = 'draft'::text))));
alter policy eq_insert on public.external_quotes with check ((created_by = (select auth.uid())));
alter policy eq_select on public.external_quotes using (((created_by = (select auth.uid())) OR is_admin_or_financial((select auth.uid()))));
alter policy eq_update on public.external_quotes using ((((created_by = (select auth.uid())) AND (status = ANY (ARRAY['draft'::text, 'rejected'::text]))) OR is_admin_or_financial((select auth.uid())))) with check ((((created_by = (select auth.uid())) AND (status = ANY (ARRAY['draft'::text, 'submitted'::text, 'rejected'::text]))) OR is_admin_or_financial((select auth.uid()))));
alter policy finance_review_select on public.finance_review_queue using (is_admin_or_financial((select auth.uid())));
alter policy finance_review_write on public.finance_review_queue using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy finance_rules_select on public.finance_rules using (is_admin_or_financial((select auth.uid())));
alter policy finance_rules_write on public.finance_rules using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy authenticated_all_financial_categories on public.financial_categories using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy fed_delete on public.fiscal_emission_drafts using (is_admin((select auth.uid())));
alter policy fed_insert on public.fiscal_emission_drafts with check (is_admin((select auth.uid())));
alter policy fed_select on public.fiscal_emission_drafts using (is_admin((select auth.uid())));
alter policy fed_update on public.fiscal_emission_drafts using (is_admin((select auth.uid())));
alter policy authenticated_all_fiscal_note_items on public.fiscal_note_items using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_fiscal_notes on public.fiscal_notes using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy fiscal_notes_insert on public.fiscal_notes with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy fiscal_notes_select on public.fiscal_notes using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy fiscal_notes_update on public.fiscal_notes using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_import_sessions on public.import_sessions using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_inventory_movements on public.inventory_movements using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy invoices_delete on public.invoices using (is_admin_or_financial((select auth.uid())));
alter policy invoices_insert on public.invoices with check (is_admin_or_financial((select auth.uid())));
alter policy invoices_select on public.invoices using (is_admin_or_financial((select auth.uid())));
alter policy invoices_update on public.invoices using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy ifd_select on public.issued_fiscal_documents using (is_admin((select auth.uid())));
alter policy legacy_hits_select_admin on public.legacy_screen_hits using (is_admin((select auth.uid())));
alter policy authenticated_all_maintenance_plans on public.maintenance_plans using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_marinas on public.marinas using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy payables_delete on public.payables using ((is_admin_or_financial((select auth.uid())) AND (is_admin((select auth.uid())) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
alter policy payables_insert on public.payables with check ((is_admin_or_financial((select auth.uid())) AND (is_admin((select auth.uid())) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
alter policy payables_select on public.payables using ((is_admin_or_financial((select auth.uid())) AND (is_admin((select auth.uid())) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
alter policy payables_update on public.payables using ((is_admin_or_financial((select auth.uid())) AND (is_admin((select auth.uid())) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category))))) with check ((is_admin_or_financial((select auth.uid())) AND (is_admin((select auth.uid())) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
alter policy payees_select on public.payees using (is_admin_or_financial((select auth.uid())));
alter policy payees_write on public.payees using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy payment_condition_presets_delete_admin on public.payment_condition_presets using (is_admin((select auth.uid())));
alter policy payment_condition_presets_insert_auth on public.payment_condition_presets with check (((select auth.uid()) IS NOT NULL));
alter policy payment_condition_presets_select_auth on public.payment_condition_presets using (((select auth.uid()) IS NOT NULL));
alter policy payment_condition_presets_update_auth on public.payment_condition_presets using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy payments_delete on public.payments using (is_admin_or_financial((select auth.uid())));
alter policy payments_insert on public.payments with check (is_admin_or_financial((select auth.uid())));
alter policy payments_select on public.payments using (is_admin_or_financial((select auth.uid())));
alter policy payments_update on public.payments using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy payroll_lines_read on public.payroll_lines using ((pode_ver_folha((select auth.uid())) OR (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = payroll_lines.work_profile_id) AND (p.app_user_id = (select auth.uid())))))));
alter policy payroll_lines_write on public.payroll_lines using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy payroll_periods_read on public.payroll_periods using (pode_ver_folha((select auth.uid())));
alter policy payroll_periods_write on public.payroll_periods using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy "admin fecha periodo" on public.periodos_fechados with check (is_admin((select auth.uid())));
alter policy "admin reabre periodo" on public.periodos_fechados using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy "financeiro le periodos" on public.periodos_fechados using (is_admin_or_financial((select auth.uid())));
alter policy "Enable all for authenticated users" on public.price_update_suggestions using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy pus_all_authenticated on public.price_update_suggestions using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_product_aliases on public.product_aliases using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_product_categories on public.product_categories using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy product_components_rw on public.product_components using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy "Enable all for authenticated users" on public.product_price_history using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy pph_all_authenticated on public.product_price_history using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_product_suppliers on public.product_suppliers using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_products on public.products using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy psbpv2_admin_select on public.products_stock_backup_pre_v2 using (is_admin((select auth.uid())));
alter policy purchase_order_items_delete on public.purchase_order_items using (is_admin_or_financial((select auth.uid())));
alter policy purchase_order_items_insert on public.purchase_order_items with check (is_admin_or_financial((select auth.uid())));
alter policy purchase_order_items_select on public.purchase_order_items using (is_admin_or_financial((select auth.uid())));
alter policy purchase_order_items_update on public.purchase_order_items using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy purchase_orders_delete on public.purchase_orders using (is_admin_or_financial((select auth.uid())));
alter policy purchase_orders_insert on public.purchase_orders with check (is_admin_or_financial((select auth.uid())));
alter policy purchase_orders_select on public.purchase_orders using (is_admin_or_financial((select auth.uid())));
alter policy purchase_orders_update on public.purchase_orders using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy push_own on public.push_subscriptions using ((user_id = (select auth.uid()))) with check ((user_id = (select auth.uid())));
alter policy quote_request_items_delete on public.quote_request_items using (is_admin_or_financial((select auth.uid())));
alter policy quote_request_items_insert on public.quote_request_items with check (is_admin_or_financial((select auth.uid())));
alter policy quote_request_items_select on public.quote_request_items using (is_admin_or_financial((select auth.uid())));
alter policy quote_request_items_update on public.quote_request_items using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy quote_request_sends_delete on public.quote_request_sends using (is_admin_or_financial((select auth.uid())));
alter policy quote_request_sends_insert on public.quote_request_sends with check (is_admin_or_financial((select auth.uid())));
alter policy quote_request_sends_select on public.quote_request_sends using (is_admin_or_financial((select auth.uid())));
alter policy quote_request_sends_update on public.quote_request_sends using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy quote_requests_delete on public.quote_requests using (is_admin_or_financial((select auth.uid())));
alter policy quote_requests_insert on public.quote_requests with check (is_admin_or_financial((select auth.uid())));
alter policy quote_requests_select on public.quote_requests using (is_admin_or_financial((select auth.uid())));
alter policy quote_requests_update on public.quote_requests using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy quote_responses_delete on public.quote_responses using (is_admin_or_financial((select auth.uid())));
alter policy quote_responses_insert on public.quote_responses with check (is_admin_or_financial((select auth.uid())));
alter policy quote_responses_select on public.quote_responses using (is_admin_or_financial((select auth.uid())));
alter policy quote_responses_update on public.quote_responses using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy receivables_delete on public.receivables using (is_admin_or_financial((select auth.uid())));
alter policy receivables_insert on public.receivables with check (is_admin_or_financial((select auth.uid())));
alter policy receivables_select on public.receivables using (is_admin_or_financial((select auth.uid())));
alter policy receivables_update on public.receivables using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy "financeiro le a trilha" on public.reconciliation_log using (is_admin_or_financial((select auth.uid())));
alter policy reconciliation_memory_select on public.reconciliation_memory using (((select auth.uid()) IS NOT NULL));
alter policy reconciliation_memory_write on public.reconciliation_memory using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_saved_filters on public.saved_filters using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy service_cases_all on public.service_cases using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_fiscal_verbs_read on public.service_fiscal_verbs using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_fiscal_verbs_write on public.service_fiscal_verbs using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy authenticated_all_service_order_expenses on public.service_order_expenses using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_service_order_parts on public.service_order_parts using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy so_photos_auth on public.service_order_photos using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_service_order_services on public.service_order_services using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy auth_read_signatures on public.service_order_signatures using (((select auth.uid()) IS NOT NULL));
alter policy auth_update_signatures on public.service_order_signatures using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy service_order_steps_all on public.service_order_steps using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_service_order_technicians on public.service_order_technicians using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_service_orders on public.service_orders using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy service_step_blocks_all on public.service_step_blocks using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_step_templates_all on public.service_step_templates using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_survey_answers_all on public.service_survey_answers using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_survey_templates_all on public.service_survey_templates using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_surveys_all on public.service_surveys using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_systems_read on public.service_systems using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_systems_write on public.service_systems using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy service_verbs_read on public.service_verbs using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy service_verbs_write on public.service_verbs using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy authenticated_all_services on public.services using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy "Enable all for authenticated users" on public.supplier_product_mappings using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy spm_all_authenticated on public.supplier_product_mappings using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy authenticated_all_suppliers on public.suppliers using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy smr_write on public.survey_material_rules using ((NOT is_external_seller((select auth.uid())))) with check ((NOT is_external_seller((select auth.uid()))));
alter policy task_reminders_all on public.task_reminders using ((((select auth.uid()) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM agenda_tasks t
  WHERE (t.id = task_reminders.task_id))))) with check ((((select auth.uid()) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM agenda_tasks t
  WHERE (t.id = task_reminders.task_id)))));
alter policy authenticated_all_time_entries on public.time_entries using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_vessel_contacts on public.vessel_contacts using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_vessels on public.vessels using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy auth_all_blocked on public.whatsapp_blocked_numbers using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy auth_all_assign on public.whatsapp_conversation_assignments using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy "Authenticated users can delete leads" on public.whatsapp_leads using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can insert leads" on public.whatsapp_leads with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can update leads" on public.whatsapp_leads using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can view leads" on public.whatsapp_leads using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can delete messages" on public.whatsapp_messages using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can insert messages" on public.whatsapp_messages with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can update messages" on public.whatsapp_messages using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy "Authenticated users can view messages" on public.whatsapp_messages using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy auth_all_quick on public.whatsapp_quick_replies using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy whatsapp_read_state_self on public.whatsapp_read_state using (((select auth.uid()) = user_id)) with check (((select auth.uid()) = user_id));
alter policy whatsapp_scheduled_sends_all_auth on public.whatsapp_scheduled_sends using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy authenticated_all_wa_queue on public.whatsapp_send_queue using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy whatsapp_status_scheduled_all_auth on public.whatsapp_status_scheduled using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));
alter policy whatsapp_templates_all_auth on public.whatsapp_templates using (((select auth.uid()) IS NOT NULL)) with check (((select auth.uid()) IS NOT NULL));
alter policy work_profiles_read on public.work_profiles using ((pode_ver_folha((select auth.uid())) OR (app_user_id = (select auth.uid()))));
alter policy work_profiles_write on public.work_profiles using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy work_shifts_delete on public.work_shifts using (is_admin((select auth.uid())));
alter policy work_shifts_insert_proprio on public.work_shifts with check ((pode_ver_folha((select auth.uid())) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = (select auth.uid()))))))));
alter policy work_shifts_read on public.work_shifts using ((pode_ver_folha((select auth.uid())) OR (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = (select auth.uid())))))));
alter policy work_shifts_update_proprio on public.work_shifts using ((pode_ver_folha((select auth.uid())) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = (select auth.uid())))))))) with check ((pode_ver_folha((select auth.uid())) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = (select auth.uid()))))))));
alter policy work_stop_reasons_write on public.work_stop_reasons using ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller))) with check ((NOT ( SELECT is_external_seller((select auth.uid())) AS is_external_seller)));

insert into supabase_migrations.schema_migrations (version, name)

values ('20260915130000', 'rls_auth_uid_uma_vez_por_consulta')

on conflict do nothing;
