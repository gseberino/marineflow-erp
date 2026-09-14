-- 08 · Políticas de RLS (public e storage)
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.


-- ── public.agenda_detector_exclusions ──
CREATE POLICY "agenda_detector_exclusions_all" ON public.agenda_detector_exclusions AS PERMISSIVE FOR ALL TO public
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.agenda_suggestions ──
CREATE POLICY "agenda_suggestions_select" ON public.agenda_suggestions AS PERMISSIVE FOR SELECT TO public
  USING (((auth.uid() IS NOT NULL) AND ((target_user_id IS NULL) OR (target_user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text) AND u.active))))));
CREATE POLICY "agenda_suggestions_update" ON public.agenda_suggestions AS PERMISSIVE FOR UPDATE TO public
  USING (((auth.uid() IS NOT NULL) AND ((target_user_id IS NULL) OR (target_user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text) AND u.active))))))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.agenda_tasks ──
CREATE POLICY "agenda_tasks_delete" ON public.agenda_tasks AS PERMISSIVE FOR DELETE TO public
  USING (((auth.uid() IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = auth.uid()) OR (created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text) AND u.active))))));
CREATE POLICY "agenda_tasks_insert" ON public.agenda_tasks AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((auth.uid() IS NOT NULL));
CREATE POLICY "agenda_tasks_select" ON public.agenda_tasks AS PERMISSIVE FOR SELECT TO public
  USING (((auth.uid() IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = auth.uid()) OR (created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text) AND u.active))))));
CREATE POLICY "agenda_tasks_update" ON public.agenda_tasks AS PERMISSIVE FOR UPDATE TO public
  USING (((auth.uid() IS NOT NULL) AND ((NOT is_private) OR (assignee_user_id = auth.uid()) OR (created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text) AND u.active))))))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.ai_agent_memory ──
CREATE POLICY "ai_memory_read" ON public.ai_agent_memory AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_agent_tasks ──
CREATE POLICY "ai_agent_tasks_read" ON public.ai_agent_tasks AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_business_alerts ──
CREATE POLICY "ai_alerts_read" ON public.ai_business_alerts AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_comms_log ──
CREATE POLICY "authenticated_all_ai_comms_log" ON public.ai_comms_log AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.ai_correction_patterns ──
CREATE POLICY "ai_corrections_insert" ON public.ai_correction_patterns AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (private.ai_op_is_active(auth.uid()));
CREATE POLICY "ai_corrections_read" ON public.ai_correction_patterns AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_daily_briefings ──
CREATE POLICY "ai_briefings_read" ON public.ai_daily_briefings AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_inbound_sessions ──
CREATE POLICY "ai_inbound_sessions_read" ON public.ai_inbound_sessions AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_learned_routines ──
CREATE POLICY "ai_learned_routines_all" ON public.ai_learned_routines AS PERMISSIVE FOR ALL TO public
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.ai_lifecycle_events ──
CREATE POLICY "ai_lifecycle_events_read" ON public.ai_lifecycle_events AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- ── public.ai_message_feedback ──
CREATE POLICY "authenticated_all_ai_message_feedback" ON public.ai_message_feedback AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.ai_operator_audit ──
CREATE POLICY "ai_op_audit_select" ON public.ai_operator_audit AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_admin_or_financial(auth.uid()));

-- ── public.ai_operator_channel_events ──
CREATE POLICY "ai_op_channel_events_select" ON public.ai_operator_channel_events AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_admin(auth.uid()));

-- ── public.ai_operator_draft_items ──
CREATE POLICY "ai_op_draft_items_select" ON public.ai_operator_draft_items AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND (EXISTS ( SELECT 1
   FROM ai_operator_drafts d
  WHERE ((d.id = ai_operator_draft_items.draft_id) AND ((d.created_by = auth.uid()) OR private.ai_op_is_admin(auth.uid()) OR (EXISTS ( SELECT 1
           FROM ai_operator_sessions s
          WHERE ((s.id = d.session_id) AND (s.owner_user_id = auth.uid()))))))))));

-- ── public.ai_operator_drafts ──
CREATE POLICY "ai_op_drafts_select" ON public.ai_operator_drafts AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND ((created_by = auth.uid()) OR private.ai_op_is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_drafts.session_id) AND (s.owner_user_id = auth.uid())))))));

-- ── public.ai_operator_memory_notes ──
CREATE POLICY "ai_op_memory_select" ON public.ai_operator_memory_notes AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND (((verification_status = 'verified'::text) AND private.ai_op_is_internal(auth.uid())) OR ((verification_status = ANY (ARRAY['candidate'::text, 'rejected'::text])) AND (private.ai_op_is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM app_users au
  WHERE ((au.id = auth.uid()) AND (au.active = true) AND (au.role = 'technician'::text)))) OR (created_by = auth.uid()))))));

-- ── public.ai_operator_messages ──
CREATE POLICY "ai_op_messages_select" ON public.ai_operator_messages AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_messages.session_id) AND ((s.owner_user_id = auth.uid()) OR private.ai_op_is_admin(auth.uid())))))));

-- ── public.ai_operator_pending_actions ──
CREATE POLICY "ai_op_pending_select" ON public.ai_operator_pending_actions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND ((requested_by_user_id = auth.uid()) OR private.ai_op_is_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM ai_operator_sessions s
  WHERE ((s.id = ai_operator_pending_actions.session_id) AND (s.owner_user_id = auth.uid())))))));

-- ── public.ai_operator_sessions ──
CREATE POLICY "ai_op_sessions_select" ON public.ai_operator_sessions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((private.ai_op_is_active(auth.uid()) AND ((owner_user_id = auth.uid()) OR private.ai_op_is_admin(auth.uid()))));

-- ── public.ai_suggestion_reviews ──
CREATE POLICY "ai_suggestion_reviews_all" ON public.ai_suggestion_reviews AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.ai_workflows ──
CREATE POLICY "ai_workflows_read" ON public.ai_workflows AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.ai_op_is_active(auth.uid()));
CREATE POLICY "ai_workflows_write" ON public.ai_workflows AS PERMISSIVE FOR ALL TO authenticated
  USING (private.ai_op_is_active(auth.uid()))
  WITH CHECK (private.ai_op_is_active(auth.uid()));

-- ── public.api_references ──
CREATE POLICY "api_references_read_auth" ON public.api_references AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.app_error_logs ──
CREATE POLICY "app_error_logs_admin_select" ON public.app_error_logs AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "app_error_logs_admin_update" ON public.app_error_logs AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin(auth.uid()));

-- ── public.app_notifications ──
CREATE POLICY "app_notifications_select" ON public.app_notifications AS PERMISSIVE FOR SELECT TO public
  USING ((user_id = auth.uid()));
CREATE POLICY "app_notifications_update" ON public.app_notifications AS PERMISSIVE FOR UPDATE TO public
  USING ((user_id = auth.uid()))
  WITH CHECK ((user_id = auth.uid()));

-- ── public.app_settings ──
CREATE POLICY "anon_public_settings_whitelist" ON public.app_settings AS PERMISSIVE FOR SELECT TO anon
  USING (((key ~~ 'public_view_%'::text) OR (key = ANY (ARRAY['company_name'::text, 'company_logo_url'::text, 'company_address'::text, 'company_city'::text, 'company_state'::text, 'company_neighborhood'::text, 'company_postal_code'::text, 'company_country'::text, 'address_line_1'::text, 'address_number'::text, 'neighborhood'::text, 'city'::text, 'state'::text, 'postal_code'::text, 'phone'::text, 'email'::text, 'cnpj'::text, 'pix_key'::text, 'bank_name'::text, 'bank_agency'::text, 'bank_account'::text, 'app_public_url'::text, 'base_currency'::text, 'display_currency'::text, 'language'::text, 'card_fee_percent'::text, 'terms_general'::text, 'terms_warranty'::text, 'terms_cancellation'::text, 'terms_delivery'::text, 'terms_responsibilities'::text]))));
CREATE POLICY "app_settings_auth_delete" ON public.app_settings AS PERMISSIVE FOR DELETE TO authenticated
  USING ((is_admin_or_financial(auth.uid()) AND (key <> 'cron_worker_secret'::text)));
CREATE POLICY "app_settings_auth_insert" ON public.app_settings AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((is_admin_or_financial(auth.uid()) AND (key <> 'cron_worker_secret'::text)));
CREATE POLICY "app_settings_auth_select" ON public.app_settings AS PERMISSIVE FOR SELECT TO authenticated
  USING ((key <> 'cron_worker_secret'::text));
CREATE POLICY "app_settings_auth_update" ON public.app_settings AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((is_admin_or_financial(auth.uid()) AND (key <> 'cron_worker_secret'::text)))
  WITH CHECK ((is_admin_or_financial(auth.uid()) AND (key <> 'cron_worker_secret'::text)));
CREATE POLICY "deny_internal_secrets" ON public.app_settings AS RESTRICTIVE FOR ALL TO anon, authenticated
  USING (((key !~~ 'cron_%'::text) AND (key !~~ 'internal_%'::text)))
  WITH CHECK (((key !~~ 'cron_%'::text) AND (key !~~ 'internal_%'::text)));

-- ── public.app_users ──
CREATE POLICY "app_users_delete_admin_only" ON public.app_users AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "app_users_insert_admin_only" ON public.app_users AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "app_users_select_self_or_admin" ON public.app_users AS PERMISSIVE FOR SELECT TO authenticated
  USING (((auth.uid() = id) OR is_admin(auth.uid())));
CREATE POLICY "app_users_update_admin_only" ON public.app_users AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.audit_log ──
CREATE POLICY "audit_log_insert_auth" ON public.audit_log AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((auth.uid() IS NOT NULL));
CREATE POLICY "audit_log_select_auth" ON public.audit_log AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));

-- ── public.bank_balance_checks ──
CREATE POLICY "financeiro le conferencias de saldo" ON public.bank_balance_checks AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));

-- ── public.bank_charges ──
CREATE POLICY "bank_charges_select" ON public.bank_charges AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "bank_charges_write" ON public.bank_charges AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.bank_connections ──
CREATE POLICY "bank_connections_select" ON public.bank_connections AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "bank_connections_write" ON public.bank_connections AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.bank_transactions ──
CREATE POLICY "bank_transactions_delete" ON public.bank_transactions AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "bank_transactions_insert" ON public.bank_transactions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "bank_transactions_select" ON public.bank_transactions AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "bank_transactions_update" ON public.bank_transactions AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.card_installment_fees ──
CREATE POLICY "card_fees_delete_admin_financial" ON public.card_installment_fees AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "card_fees_read_authenticated" ON public.card_installment_fees AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "card_fees_update_admin_financial" ON public.card_installment_fees AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "card_fees_write_admin_financial" ON public.card_installment_fees AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.client_whatsapp_settings ──
CREATE POLICY "client_whatsapp_settings_all_auth" ON public.client_whatsapp_settings AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.clients ──
CREATE POLICY "anon_clients_via_share_token" ON public.clients AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.client_id = clients.id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_clients" ON public.clients AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.collection_contacts ──
CREATE POLICY "authenticated_full_access" ON public.collection_contacts AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.collection_templates ──
CREATE POLICY "authenticated_full_access" ON public.collection_templates AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.collections ──
CREATE POLICY "authenticated_full_access" ON public.collections AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.commissions ──
CREATE POLICY "Admins can do everything on commissions" ON public.commissions AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "Users can view own commissions" ON public.commissions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() = user_id));
CREATE POLICY "commissions_admin_all" ON public.commissions AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "commissions_self_select" ON public.commissions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() = user_id));

-- ── public.company_fiscal_settings ──
CREATE POLICY "cfs_insert" ON public.company_fiscal_settings AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "cfs_select" ON public.company_fiscal_settings AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "cfs_update" ON public.company_fiscal_settings AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin(auth.uid()));

-- ── public.cost_centers ──
CREATE POLICY "Enable read/write for all authenticated users" ON public.cost_centers AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "cost_centers_all_authenticated" ON public.cost_centers AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.dc_ampacity_ratings ──
CREATE POLICY "dc_amp_select" ON public.dc_ampacity_ratings AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "dc_amp_write" ON public.dc_ampacity_ratings AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT is_external_seller(auth.uid())))
  WITH CHECK ((NOT is_external_seller(auth.uid())));

-- ── public.entity_open_loops ──
CREATE POLICY "entity_open_loops_all" ON public.entity_open_loops AS PERMISSIVE FOR ALL TO public
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.exchange_rates ──
CREATE POLICY "authenticated_all_exchange_rates" ON public.exchange_rates AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.external_quote_leads ──
CREATE POLICY "eql_delete" ON public.external_quote_leads AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "eql_insert" ON public.external_quote_leads AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((created_by = auth.uid()));
CREATE POLICY "eql_select" ON public.external_quote_leads AS PERMISSIVE FOR SELECT TO authenticated
  USING (((created_by = auth.uid()) OR is_admin_or_financial(auth.uid())));
CREATE POLICY "eql_update" ON public.external_quote_leads AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((created_by = auth.uid()) OR is_admin_or_financial(auth.uid())))
  WITH CHECK (((created_by = auth.uid()) OR is_admin_or_financial(auth.uid())));

-- ── public.external_quote_parts ──
CREATE POLICY "eqp_all" ON public.external_quote_parts AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_parts.external_quote_id) AND ((q.created_by = auth.uid()) OR is_admin_or_financial(auth.uid()))))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_parts.external_quote_id) AND ((q.created_by = auth.uid()) OR is_admin_or_financial(auth.uid()))))));

-- ── public.external_quote_services ──
CREATE POLICY "eqs_all" ON public.external_quote_services AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_services.external_quote_id) AND ((q.created_by = auth.uid()) OR is_admin_or_financial(auth.uid()))))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM external_quotes q
  WHERE ((q.id = external_quote_services.external_quote_id) AND ((q.created_by = auth.uid()) OR is_admin_or_financial(auth.uid()))))));

-- ── public.external_quotes ──
CREATE POLICY "eq_delete" ON public.external_quotes AS PERMISSIVE FOR DELETE TO authenticated
  USING ((is_admin_or_financial(auth.uid()) OR ((created_by = auth.uid()) AND (status = 'draft'::text))));
CREATE POLICY "eq_insert" ON public.external_quotes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((created_by = auth.uid()));
CREATE POLICY "eq_select" ON public.external_quotes AS PERMISSIVE FOR SELECT TO authenticated
  USING (((created_by = auth.uid()) OR is_admin_or_financial(auth.uid())));
CREATE POLICY "eq_update" ON public.external_quotes AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((((created_by = auth.uid()) AND (status = ANY (ARRAY['draft'::text, 'rejected'::text]))) OR is_admin_or_financial(auth.uid())))
  WITH CHECK ((((created_by = auth.uid()) AND (status = ANY (ARRAY['draft'::text, 'submitted'::text, 'rejected'::text]))) OR is_admin_or_financial(auth.uid())));

-- ── public.finance_review_queue ──
CREATE POLICY "finance_review_select" ON public.finance_review_queue AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "finance_review_write" ON public.finance_review_queue AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.finance_rules ──
CREATE POLICY "finance_rules_select" ON public.finance_rules AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "finance_rules_write" ON public.finance_rules AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.financial_categories ──
CREATE POLICY "authenticated_all_financial_categories" ON public.financial_categories AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.fiscal_emission_drafts ──
CREATE POLICY "fed_delete" ON public.fiscal_emission_drafts AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "fed_insert" ON public.fiscal_emission_drafts AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "fed_select" ON public.fiscal_emission_drafts AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "fed_update" ON public.fiscal_emission_drafts AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin(auth.uid()));

-- ── public.fiscal_note_items ──
CREATE POLICY "authenticated_all_fiscal_note_items" ON public.fiscal_note_items AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.fiscal_notes ──
CREATE POLICY "authenticated_all_fiscal_notes" ON public.fiscal_notes AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "fiscal_notes_insert" ON public.fiscal_notes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "fiscal_notes_select" ON public.fiscal_notes AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "fiscal_notes_update" ON public.fiscal_notes AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.import_sessions ──
CREATE POLICY "authenticated_all_import_sessions" ON public.import_sessions AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.inventory_movements ──
CREATE POLICY "authenticated_all_inventory_movements" ON public.inventory_movements AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.invoices ──
CREATE POLICY "invoices_delete" ON public.invoices AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "invoices_insert" ON public.invoices AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "invoices_select" ON public.invoices AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "invoices_update" ON public.invoices AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.issued_fiscal_documents ──
CREATE POLICY "ifd_select" ON public.issued_fiscal_documents AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin(auth.uid()));

-- ── public.maintenance_plans ──
CREATE POLICY "authenticated_all_maintenance_plans" ON public.maintenance_plans AS PERMISSIVE FOR ALL TO public
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.marinas ──
CREATE POLICY "anon_marinas_via_share_token" ON public.marinas AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.marina_id = marinas.id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_marinas" ON public.marinas AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.payables ──
CREATE POLICY "payables_delete" ON public.payables AS PERMISSIVE FOR DELETE TO authenticated
  USING ((is_admin_or_financial(auth.uid()) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
CREATE POLICY "payables_insert" ON public.payables AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((is_admin_or_financial(auth.uid()) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
CREATE POLICY "payables_select" ON public.payables AS PERMISSIVE FOR SELECT TO authenticated
  USING ((is_admin_or_financial(auth.uid()) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));
CREATE POLICY "payables_update" ON public.payables AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((is_admin_or_financial(auth.uid()) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))))
  WITH CHECK ((is_admin_or_financial(auth.uid()) AND (is_admin(auth.uid()) OR (expense_category IS NULL) OR (NOT categoria_e_sensivel(expense_category)))));

-- ── public.payees ──
CREATE POLICY "payees_select" ON public.payees AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "payees_write" ON public.payees AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.payment_condition_presets ──
CREATE POLICY "anon_payment_condition_presets_via_share_token" ON public.payment_condition_presets AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.payment_condition_preset_id = payment_condition_presets.id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "payment_condition_presets_delete_admin" ON public.payment_condition_presets AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "payment_condition_presets_insert_auth" ON public.payment_condition_presets AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((auth.uid() IS NOT NULL));
CREATE POLICY "payment_condition_presets_select_auth" ON public.payment_condition_presets AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "payment_condition_presets_update_auth" ON public.payment_condition_presets AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.payments ──
CREATE POLICY "anon_payments_via_share_token" ON public.payments AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM (receivables r
     JOIN service_orders so ON ((so.id = r.service_order_id)))
  WHERE ((r.id = payments.receivable_id) AND (so.share_token IS NOT NULL) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "payments_delete" ON public.payments AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "payments_insert" ON public.payments AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "payments_select" ON public.payments AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "payments_update" ON public.payments AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.payroll_lines ──
CREATE POLICY "payroll_lines_read" ON public.payroll_lines AS PERMISSIVE FOR SELECT TO authenticated
  USING ((pode_ver_folha(auth.uid()) OR (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = payroll_lines.work_profile_id) AND (p.app_user_id = auth.uid()))))));
CREATE POLICY "payroll_lines_write" ON public.payroll_lines AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.payroll_periods ──
CREATE POLICY "payroll_periods_read" ON public.payroll_periods AS PERMISSIVE FOR SELECT TO authenticated
  USING (pode_ver_folha(auth.uid()));
CREATE POLICY "payroll_periods_write" ON public.payroll_periods AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.periodos_fechados ──
CREATE POLICY "admin fecha periodo" ON public.periodos_fechados AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "admin reabre periodo" ON public.periodos_fechados AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));
CREATE POLICY "financeiro le periodos" ON public.periodos_fechados AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));

-- ── public.price_update_suggestions ──
CREATE POLICY "Enable all for authenticated users" ON public.price_update_suggestions AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "pus_all_authenticated" ON public.price_update_suggestions AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.product_aliases ──
CREATE POLICY "authenticated_all_product_aliases" ON public.product_aliases AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.product_categories ──
CREATE POLICY "authenticated_all_product_categories" ON public.product_categories AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.product_components ──
CREATE POLICY "product_components_rw" ON public.product_components AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.product_price_history ──
CREATE POLICY "Enable all for authenticated users" ON public.product_price_history AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "pph_all_authenticated" ON public.product_price_history AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.product_suppliers ──
CREATE POLICY "authenticated_all_product_suppliers" ON public.product_suppliers AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.products ──
CREATE POLICY "anon_products_via_share_token" ON public.products AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM (service_order_parts sp
     JOIN service_orders so ON ((so.id = sp.service_order_id)))
  WHERE ((sp.product_id = products.id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_products" ON public.products AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.products_stock_backup_pre_v2 ──
CREATE POLICY "psbpv2_admin_select" ON public.products_stock_backup_pre_v2 AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin(auth.uid()));

-- ── public.purchase_order_items ──
CREATE POLICY "purchase_order_items_delete" ON public.purchase_order_items AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_order_items_insert" ON public.purchase_order_items AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_order_items_select" ON public.purchase_order_items AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_order_items_update" ON public.purchase_order_items AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.purchase_orders ──
CREATE POLICY "purchase_orders_delete" ON public.purchase_orders AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_orders_insert" ON public.purchase_orders AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_orders_select" ON public.purchase_orders AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "purchase_orders_update" ON public.purchase_orders AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.push_subscriptions ──
CREATE POLICY "push_own" ON public.push_subscriptions AS PERMISSIVE FOR ALL TO authenticated
  USING ((user_id = auth.uid()))
  WITH CHECK ((user_id = auth.uid()));

-- ── public.quote_request_items ──
CREATE POLICY "quote_request_items_delete" ON public.quote_request_items AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_items_insert" ON public.quote_request_items AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_items_select" ON public.quote_request_items AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_items_update" ON public.quote_request_items AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.quote_request_sends ──
CREATE POLICY "quote_request_sends_delete" ON public.quote_request_sends AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_sends_insert" ON public.quote_request_sends AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_sends_select" ON public.quote_request_sends AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_request_sends_update" ON public.quote_request_sends AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.quote_requests ──
CREATE POLICY "quote_requests_delete" ON public.quote_requests AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_requests_insert" ON public.quote_requests AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_requests_select" ON public.quote_requests AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_requests_update" ON public.quote_requests AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.quote_responses ──
CREATE POLICY "quote_responses_delete" ON public.quote_responses AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_responses_insert" ON public.quote_responses AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_responses_select" ON public.quote_responses AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "quote_responses_update" ON public.quote_responses AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.receivables ──
CREATE POLICY "anon_receivables_via_share_token" ON public.receivables AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = receivables.service_order_id) AND (so.share_token IS NOT NULL) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "receivables_delete" ON public.receivables AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "receivables_insert" ON public.receivables AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (is_admin_or_financial(auth.uid()));
CREATE POLICY "receivables_select" ON public.receivables AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));
CREATE POLICY "receivables_update" ON public.receivables AS PERMISSIVE FOR UPDATE TO authenticated
  USING (is_admin_or_financial(auth.uid()))
  WITH CHECK (is_admin_or_financial(auth.uid()));

-- ── public.reconciliation_log ──
CREATE POLICY "financeiro le a trilha" ON public.reconciliation_log AS PERMISSIVE FOR SELECT TO authenticated
  USING (is_admin_or_financial(auth.uid()));

-- ── public.reconciliation_memory ──
CREATE POLICY "reconciliation_memory_select" ON public.reconciliation_memory AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "reconciliation_memory_write" ON public.reconciliation_memory AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.saved_filters ──
CREATE POLICY "authenticated_all_saved_filters" ON public.saved_filters AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_cases ──
CREATE POLICY "service_cases_all" ON public.service_cases AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_fiscal_verbs ──
CREATE POLICY "service_fiscal_verbs_read" ON public.service_fiscal_verbs AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "service_fiscal_verbs_write" ON public.service_fiscal_verbs AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.service_order_expenses ──
CREATE POLICY "anon_so_expenses_via_share_token" ON public.service_order_expenses AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = service_order_expenses.service_order_id) AND (so.share_token IS NOT NULL) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_service_order_expenses" ON public.service_order_expenses AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_order_parts ──
CREATE POLICY "anon_service_order_parts_via_share_token" ON public.service_order_parts AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = service_order_parts.service_order_id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_service_order_parts" ON public.service_order_parts AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_order_photos ──
CREATE POLICY "so_photos_auth" ON public.service_order_photos AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_order_services ──
CREATE POLICY "anon_service_order_services_via_share_token" ON public.service_order_services AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = service_order_services.service_order_id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_service_order_services" ON public.service_order_services AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_order_signatures ──
CREATE POLICY "anon_read_signatures_by_token" ON public.service_order_signatures AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = service_order_signatures.service_order_id) AND (so.share_token IS NOT NULL) AND (so.share_token = service_order_signatures.share_token)))));
CREATE POLICY "auth_read_signatures" ON public.service_order_signatures AS PERMISSIVE FOR SELECT TO authenticated
  USING ((auth.uid() IS NOT NULL));
CREATE POLICY "auth_update_signatures" ON public.service_order_signatures AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_order_steps ──
CREATE POLICY "service_order_steps_all" ON public.service_order_steps AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_order_technicians ──
CREATE POLICY "authenticated_all_service_order_technicians" ON public.service_order_technicians AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_orders ──
CREATE POLICY "anon_service_orders_via_share_token" ON public.service_orders AS PERMISSIVE FOR SELECT TO anon
  USING (((share_token IS NOT NULL) AND ((share_token)::text = share_token_da_requisicao())));
CREATE POLICY "authenticated_all_service_orders" ON public.service_orders AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.service_step_blocks ──
CREATE POLICY "service_step_blocks_all" ON public.service_step_blocks AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_step_templates ──
CREATE POLICY "service_step_templates_all" ON public.service_step_templates AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_survey_answers ──
CREATE POLICY "anon_survey_answers_via_share_token" ON public.service_survey_answers AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM (service_surveys sv
     JOIN service_orders so ON ((so.id = sv.service_order_id)))
  WHERE ((sv.id = service_survey_answers.survey_id) AND (sv.status = 'closed'::text) AND (so.share_token IS NOT NULL) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "service_survey_answers_all" ON public.service_survey_answers AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_survey_templates ──
CREATE POLICY "service_survey_templates_all" ON public.service_survey_templates AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_surveys ──
CREATE POLICY "anon_surveys_via_share_token" ON public.service_surveys AS PERMISSIVE FOR SELECT TO anon
  USING (((status = 'closed'::text) AND (EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.id = service_surveys.service_order_id) AND (so.share_token IS NOT NULL) AND ((so.share_token)::text = share_token_da_requisicao()))))));
CREATE POLICY "service_surveys_all" ON public.service_surveys AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.service_systems ──
CREATE POLICY "service_systems_read" ON public.service_systems AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "service_systems_write" ON public.service_systems AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.service_verbs ──
CREATE POLICY "service_verbs_read" ON public.service_verbs AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "service_verbs_write" ON public.service_verbs AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.services ──
CREATE POLICY "authenticated_all_services" ON public.services AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.supplier_product_mappings ──
CREATE POLICY "Enable all for authenticated users" ON public.supplier_product_mappings AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "spm_all_authenticated" ON public.supplier_product_mappings AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.suppliers ──
CREATE POLICY "authenticated_all_suppliers" ON public.suppliers AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.survey_material_rules ──
CREATE POLICY "smr_select" ON public.survey_material_rules AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "smr_write" ON public.survey_material_rules AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT is_external_seller(auth.uid())))
  WITH CHECK ((NOT is_external_seller(auth.uid())));

-- ── public.task_reminders ──
CREATE POLICY "task_reminders_all" ON public.task_reminders AS PERMISSIVE FOR ALL TO public
  USING (((auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM agenda_tasks t
  WHERE (t.id = task_reminders.task_id)))))
  WITH CHECK (((auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM agenda_tasks t
  WHERE (t.id = task_reminders.task_id)))));

-- ── public.time_entries ──
CREATE POLICY "authenticated_all_time_entries" ON public.time_entries AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.vessel_contacts ──
CREATE POLICY "authenticated_all_vessel_contacts" ON public.vessel_contacts AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.vessels ──
CREATE POLICY "anon_vessels_via_share_token" ON public.vessels AS PERMISSIVE FOR SELECT TO anon
  USING ((EXISTS ( SELECT 1
   FROM service_orders so
  WHERE ((so.vessel_id = vessels.id) AND ((so.share_token)::text = share_token_da_requisicao())))));
CREATE POLICY "authenticated_all_vessels" ON public.vessels AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_blocked_numbers ──
CREATE POLICY "auth_all_blocked" ON public.whatsapp_blocked_numbers AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_conversation_assignments ──
CREATE POLICY "auth_all_assign" ON public.whatsapp_conversation_assignments AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_leads ──
CREATE POLICY "Authenticated users can delete leads" ON public.whatsapp_leads AS PERMISSIVE FOR DELETE TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can insert leads" ON public.whatsapp_leads AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can update leads" ON public.whatsapp_leads AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can view leads" ON public.whatsapp_leads AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.whatsapp_messages ──
CREATE POLICY "Authenticated users can delete messages" ON public.whatsapp_messages AS PERMISSIVE FOR DELETE TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can insert messages" ON public.whatsapp_messages AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can update messages" ON public.whatsapp_messages AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));
CREATE POLICY "Authenticated users can view messages" ON public.whatsapp_messages AS PERMISSIVE FOR SELECT TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.whatsapp_quick_replies ──
CREATE POLICY "auth_all_quick" ON public.whatsapp_quick_replies AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_read_state ──
CREATE POLICY "whatsapp_read_state_self" ON public.whatsapp_read_state AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() = user_id))
  WITH CHECK ((auth.uid() = user_id));

-- ── public.whatsapp_scheduled_sends ──
CREATE POLICY "whatsapp_scheduled_sends_all_auth" ON public.whatsapp_scheduled_sends AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_send_queue ──
CREATE POLICY "authenticated_all_wa_queue" ON public.whatsapp_send_queue AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.whatsapp_status_scheduled ──
CREATE POLICY "whatsapp_status_scheduled_all_auth" ON public.whatsapp_status_scheduled AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── public.whatsapp_templates ──
CREATE POLICY "whatsapp_templates_all_auth" ON public.whatsapp_templates AS PERMISSIVE FOR ALL TO authenticated
  USING ((auth.uid() IS NOT NULL))
  WITH CHECK ((auth.uid() IS NOT NULL));

-- ── public.work_profiles ──
CREATE POLICY "work_profiles_read" ON public.work_profiles AS PERMISSIVE FOR SELECT TO authenticated
  USING ((pode_ver_folha(auth.uid()) OR (app_user_id = auth.uid())));
CREATE POLICY "work_profiles_write" ON public.work_profiles AS PERMISSIVE FOR ALL TO authenticated
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- ── public.work_shifts ──
CREATE POLICY "work_shifts_delete" ON public.work_shifts AS PERMISSIVE FOR DELETE TO authenticated
  USING (is_admin(auth.uid()));
CREATE POLICY "work_shifts_insert_proprio" ON public.work_shifts AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((pode_ver_folha(auth.uid()) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = auth.uid())))))));
CREATE POLICY "work_shifts_read" ON public.work_shifts AS PERMISSIVE FOR SELECT TO authenticated
  USING ((pode_ver_folha(auth.uid()) OR (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = auth.uid()))))));
CREATE POLICY "work_shifts_update_proprio" ON public.work_shifts AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((pode_ver_folha(auth.uid()) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = auth.uid())))))))
  WITH CHECK ((pode_ver_folha(auth.uid()) OR ((status = 'rascunho'::text) AND (EXISTS ( SELECT 1
   FROM work_profiles p
  WHERE ((p.id = work_shifts.work_profile_id) AND (p.app_user_id = auth.uid())))))));

-- ── public.work_stop_reasons ──
CREATE POLICY "work_stop_reasons_read" ON public.work_stop_reasons AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "work_stop_reasons_write" ON public.work_stop_reasons AS PERMISSIVE FOR ALL TO authenticated
  USING ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)))
  WITH CHECK ((NOT ( SELECT is_external_seller(auth.uid()) AS is_external_seller)));

-- ── storage.objects ──
CREATE POLICY "company_assets_auth_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'company-assets'::text));
CREATE POLICY "company_assets_auth_update" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((bucket_id = 'company-assets'::text));
CREATE POLICY "company_assets_auth_write" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'company-assets'::text));
CREATE POLICY "company_assets_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO public
  USING ((bucket_id = 'company-assets'::text));
CREATE POLICY "documents_authenticated_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'documents'::text));
CREATE POLICY "documents_authenticated_insert" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'documents'::text));
CREATE POLICY "documents_authenticated_update" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((bucket_id = 'documents'::text))
  WITH CHECK ((bucket_id = 'documents'::text));
CREATE POLICY "documents_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING ((bucket_id = 'documents'::text));
CREATE POLICY "expense_receipts_auth_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'expense-receipts'::text));
CREATE POLICY "expense_receipts_auth_insert" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'expense-receipts'::text));
CREATE POLICY "expense_receipts_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO public
  USING ((bucket_id = 'expense-receipts'::text));
CREATE POLICY "fiscal_xml_admin_read" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'fiscal-xml'::text) AND is_admin(auth.uid())));
CREATE POLICY "product_images_auth_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'product-images'::text));
CREATE POLICY "product_images_auth_insert" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'product-images'::text));
CREATE POLICY "product_images_auth_update" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((bucket_id = 'product-images'::text));
CREATE POLICY "product_images_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO public
  USING ((bucket_id = 'product-images'::text));
CREATE POLICY "signatures_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO public
  USING ((bucket_id = 'signatures'::text));
CREATE POLICY "so_photos_bucket_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'service-order-photos'::text));
CREATE POLICY "so_photos_bucket_insert" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'service-order-photos'::text));
CREATE POLICY "so_photos_bucket_select" ON storage.objects AS PERMISSIVE FOR SELECT TO public
  USING ((bucket_id = 'service-order-photos'::text));
CREATE POLICY "so_photos_bucket_update" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((bucket_id = 'service-order-photos'::text));
CREATE POLICY "whatsapp_status_auth_delete" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING ((bucket_id = 'whatsapp_status'::text));
CREATE POLICY "whatsapp_status_auth_insert" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((bucket_id = 'whatsapp_status'::text));
CREATE POLICY "whatsapp_status_public_read" ON storage.objects AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING ((bucket_id = 'whatsapp_status'::text));
