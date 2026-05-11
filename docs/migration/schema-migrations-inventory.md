# Schema / Migrations Inventory

## Overview

- Migrations found: 85
- Edge Functions found: 18
- Tables in src/integrations/supabase/types.ts: 60
- Views in src/integrations/supabase/types.ts: 1
- Functions in src/integrations/supabase/types.ts: 12
- Backup Lovable tables: 23
- Backup duplicate key groups: clients.email (12), clients.cpf_cnpj (2), services.service_name (1)
- Internal missing references in backup analysis: 0

## Migration Groups

### Foundational / early schema
- 20260407192937_fb252897-736b-4b34-8dad-5c9e790cd924.sql ? Financeiro, Cadastros / OS
- 20260407211146_b66cd31e-560f-4a6f-8cfd-f5caa2f80f69.sql ? Financeiro, Compras, Cadastros / OS
- 20260407213415_2560ae27-ee78-441b-a057-90e5b3f4c8dd.sql ? General
- 20260407223837_f07e20fd-53c5-4613-8d51-ae6e9c9ed256.sql ? Cadastros / OS
- 20260408154132_3d263d38-54eb-4054-9afc-646a090efb16.sql ? Financeiro
- 20260408171236_f3994d12-ed02-415f-8072-8aff4c0cc423.sql ? Financeiro, Cadastros / OS
- 20260409170746_be786d9c-49c4-43f4-8d97-a0cbf5321435.sql ? Financeiro

### Core business modules
- 20260410162506_af386947-8a19-4188-9a82-80171d31fa5c.sql ? Financeiro
- 20260410172717_6ef25308-2370-4e33-b6ad-5f686bf8239a.sql ? Financeiro, Cadastros / OS
- 20260410174604_ff6a6010-389c-4f37-8a38-0f35be11fbf6.sql ? Importa??o
- 20260412165535_a0a80a2a-a19a-4f5e-83ff-3b7dfa7e164b.sql ? Cadastros / OS
- 20260412222942_b95e28f9-3e1b-408c-8a97-0f300e9d6e79.sql ? Cadastros / OS
- 20260413114221_27b4f182-71b6-4806-8f07-ddc4e1e7b43f.sql ? Cadastros / OS
- 20260413164557_c4e61486-bb90-4e60-833b-849a19e63744.sql ? Cadastros / OS
- 20260414120109_1d6f7d19-ed71-4bf7-8778-acda61114531.sql ? Cadastros / OS
- 20260415024437_328143dc-0cd6-44bb-a456-561d591053d6.sql ? Cadastros / OS
- 20260415030526_dc43dc8a-8e91-4f10-b70d-81c30d85bc6e.sql ? Cadastros / OS
- 20260417124206_6d2f5b3d-2617-4f26-8440-392879122618.sql ? Cadastros / OS
- 20260419183949_78940a7c-a2cc-486f-bd5e-a3b2d0598a95.sql ? Cadastros / OS
- 20260420110919_3267319d-76cc-4008-a86b-3c01f2bb037d.sql ? Cadastros / OS
- 20260420172126_416076db-acf2-4da6-aa90-e5e7da60f33d.sql ? Cadastros / OS

### Advanced business modules
- 20260421131952_e48d2328-b603-410c-b57f-22014e3b7820.sql ? Cadastros / OS, Views
- 20260421133233_d9d23ec7-cd12-443d-93f9-ef91fa2821b6.sql ? General
- 20260421143927_e3b7b2cc-f9df-4b21-a7e0-7471a2a81d05.sql ? Cadastros / OS
- 20260421160850_2f6c8307-6e72-4478-8d2e-3c15cdbe983b.sql ? Cadastros / OS
- 20260421161411_f41d70d9-2353-4e54-9a07-0d327ddb3aeb.sql ? General
- 20260421172230_1fd1b91a-5c9f-4276-b329-2c6aba1d2cd3.sql ? General
- 20260421172306_1b76c9a7-07c2-4482-9867-24ff370ed1b5.sql ? WhatsApp, Views
- 20260421173257_55d32894-41e2-4574-839b-fbcae0b14504.sql ? General
- 20260421174106_66f1988c-d175-4b94-a730-683eb3ae3bc7.sql ? WhatsApp
- 20260421175004_aa7d1c72-2d70-4d29-b019-19aa4ee39712.sql ? WhatsApp, Cadastros / OS
- 20260422103739_430bb285-c11d-4e3d-a0c6-644a315164d3.sql ? WhatsApp
- 20260422132644_21b0dbdd-c217-4615-9d4c-620edcd0d982.sql ? General
- 20260422141525_a0f31f6f-87f4-4a37-bc84-7fbaa790eff5.sql ? Cadastros / OS
- 20260422150335_73878813-15a8-4d90-9330-b59bbe0cf32c.sql ? Cadastros / OS
- 20260422155330_a263a2c2-22bc-4c12-b351-506c95fc51ec.sql ? Cadastros / OS
- 20260422161306_62d913f0-48ab-4d95-a24f-6fcd39c10152.sql ? Cadastros / OS
- 20260422173113_0691c013-ee5f-416a-b69f-ac328d9cf337.sql ? WhatsApp
- 20260422184141_1232e996-2c4c-4e78-a90a-be8b2d44b90f.sql ? General
- 20260422184349_8577bda0-bea7-46c1-8d33-84def727e5a6.sql ? Cadastros / OS
- 20260422190814_d85c10cc-1613-4316-8aab-e1e6938fed7e.sql ? Cadastros / OS
- 20260422191621_1e9b7383-4c62-45d0-b59b-0a0809e54895.sql ? General
- 20260422191930_2c815fbb-f744-4972-bb07-4fa802910c6f.sql ? WhatsApp
- 20260422193951_c6c59866-c3d3-49c8-b396-e3f3c056344f.sql ? General
- 20260422195258_75cc1640-e29c-4131-828c-9318157b9d57.sql ? General
- 20260422212304_00af1485-5268-4c1b-9857-4685094f1019.sql ? WhatsApp
- 20260422213234_85f12ad6-d5f4-4416-96ee-e3edbc1c503e.sql ? Cadastros / OS
- 20260423141204_5b60325d-3b8f-443d-9923-d3e2d8e9a45a.sql ? Cadastros / OS
- 20260424213018_6abbcb24-5217-4844-9a24-7eda002b114e.sql ? Cadastros / OS
- 20260424222817_bbefaaee-3df9-466c-ad35-a7a892bbe3d9.sql ? Cadastros / OS
- 20260425131630_17be375c-a12f-49c4-84c0-3f74ab872177.sql ? Cadastros / OS
- 20260425132824_5dc1b68d-3eaa-43bb-b26f-fef73f8b88d7.sql ? Cadastros / OS
- 20260425141256_3f88a6f0-851b-4ec9-8f5e-97116be7e918.sql ? General
- 20260427163648_2e827f51-fa0f-4999-886b-c3f354746422.sql ? General
- 20260428000000_add_warranty.sql ? General
- 20260428000001_inventory_tables.sql ? General
- 20260428000002_commissions.sql ? Financeiro, Views
- 20260428010000_fiscal_notes.sql ? Financeiro, Fiscal, Cadastros / OS, Importa??o
- 20260428020000_supplier_product_mappings.sql ? Compras, Fiscal, Importa??o
- 20260428022454_39950c6e-57c4-405e-acc9-bf458cd2f3c2.sql ? Fiscal, Cadastros / OS
- 20260428030000_price_intelligence.sql ? General
- 20260428040000_profitability_view.sql ? Views
- 20260428050000_performance_indices.sql ? General
- 20260428070000_asset_types.sql ? Cadastros / OS
- 20260428080000_photos.sql ? Cadastros / OS
- 20260428120000_financial_dre.sql ? Financeiro
- 20260428121826_7c58b9e4-8e9f-455c-8031-b567ff94ce2c.sql ? Financeiro, Compras, Cadastros / OS
- 20260428130000_reminders.sql ? Cadastros / OS

### Integrations / automation / late additions
- 20260430093300_add_hr_fields.sql ? Cadastros / OS
- 20260430120236_72f1a513-f610-45a3-879e-931cab6d65e3.sql ? Financeiro, Cadastros / OS
- 20260430120417_ea6c5188-efdf-4b21-91cf-870667212256.sql ? General
- 20260502221757_00b59207-9f9f-420b-9b74-bd10093b8bf7.sql ? General
- 20260502222001_c7eea97d-de32-45da-ab40-7c60881ddbd4.sql ? Cadastros / OS
- 20260502222308_70919e39-7f7f-44f2-9837-a2b55c064e3e.sql ? Cadastros / OS
- 20260502222513_1aa226ff-480a-48ff-88ab-4f30ddf9f790.sql ? Cadastros / OS
- 20260502222957_7c52675b-aa25-4176-8ec2-da79e4986a5a.sql ? General
- 20260508120000_fix_inventory_movement_type_constraint.sql ? Cadastros / OS
- 20260508130000_register_payment_rpc.sql ? RPCs / Functions
- 20260508140000_cancel_so_cascade_rpc.sql ? Cadastros / OS, RPCs / Functions
- 20260508144510_3fd6b735-2c74-42eb-997e-f42502e592c9.sql ? Cadastros / OS
- 20260508144659_1edae166-a1be-4831-b078-c78dbd4980dd.sql ? General
- 20260508_purchase_orders.sql ? Compras
- 20260509120000_whatsapp_scheduled_add_manual_target.sql ? WhatsApp
- 20260509130000_api_references_zapi.sql ? WhatsApp, Fiscal
- 20260509140000_whatsapp_status_scheduled.sql ? WhatsApp

## Chronological Migration List

| File | Tags | Created tables | Altered tables | Functions | Views | Triggers | Policies |
|---|---|---|---|---|---|---|---|
| 20260407192937_fb252897-736b-4b34-8dad-5c9e790cd924.sql | Financeiro, Cadastros / OS | app_users<br>marinas<br>clients<br>vessels<br>products<br>service_orders<br>service_order_technicians<br>service_order_parts<br>time_entries<br>inventory_movements<br>invoices<br>receivables<br>payables<br>exchange_rates<br>app_settings | app_users<br>marinas<br>clients<br>vessels<br>products<br>service_orders<br>service_order_technicians<br>service_order_parts<br>time_entries<br>inventory_movements<br>invoices<br>receivables<br>payables<br>exchange_rates<br>app_settings | update_updated_at_column | - | update_app_users_updated_at<br>update_marinas_updated_at<br>update_clients_updated_at<br>update_vessels_updated_at<br>update_products_updated_at<br>update_service_orders_updated_at<br>update_service_order_technicians_updated_at<br>update_service_order_parts_updated_at<br>update_time_entries_updated_at<br>update_invoices_updated_at<br>update_receivables_updated_at<br>update_payables_updated_at<br>update_app_settings_updated_at | Authenticated users can do everything on app_users<br>Authenticated users can do everything on marinas<br>Authenticated users can do everything on clients<br>Authenticated users can do everything on vessels<br>Authenticated users can do everything on products<br>Authenticated users can do everything on service_orders<br>Authenticated users can do everything on service_order_technicians<br>Authenticated users can do everything on service_order_parts<br>Authenticated users can do everything on time_entries<br>Authenticated users can do everything on inventory_movements<br>Authenticated users can do everything on invoices<br>Authenticated users can do everything on receivables<br>Authenticated users can do everything on payables<br>Authenticated users can do everything on exchange_rates<br>Authenticated users can do everything on app_settings |
| 20260407211146_b66cd31e-560f-4a6f-8cfd-f5caa2f80f69.sql | Financeiro, Compras, Cadastros / OS | suppliers<br>product_suppliers | payables<br>suppliers<br>product_suppliers | - | - | set_updated_at_suppliers<br>set_updated_at_product_suppliers | allow_all_suppliers<br>allow_all_product_suppliers |
| 20260407213415_2560ae27-ee78-441b-a057-90e5b3f4c8dd.sql | General | - | - | - | - | - | allow_all_%s |
| 20260407223837_f07e20fd-53c5-4613-8d51-ae6e9c9ed256.sql | Cadastros / OS | services<br>service_order_services<br>card_installment_fees | services<br>service_order_services<br>card_installment_fees | - | - | set_updated_at_services<br>set_updated_at_service_order_services | allow_all_services ON services<br>allow_all_service_order_services ON service_order_services<br>allow_all_card_fees ON card_installment_fees |
| 20260408154132_3d263d38-54eb-4054-9afc-646a090efb16.sql | Financeiro | payments<br>bank_transactions | payments<br>bank_transactions | - | - | - | allow_all_payments ON payments<br>allow_all_bank_transactions ON bank_transactions |
| 20260408171236_f3994d12-ed02-415f-8072-8aff4c0cc423.sql | Financeiro, Cadastros / OS | service_order_expenses | service_order_expenses<br>service_orders<br>bank_transactions | - | - | set_updated_at_so_expenses | allow_all_service_order_expenses ON service_order_expenses |
| 20260409170746_be786d9c-49c4-43f4-8d97-a0cbf5321435.sql | Financeiro | - | payables | - | - | - | - |
| 20260410162506_af386947-8a19-4188-9a82-80171d31fa5c.sql | Financeiro | financial_categories<br>saved_filters | financial_categories<br>saved_filters<br>receivables | - | - | - | allow_all_financial_categories ON financial_categories<br>allow_all_saved_filters ON saved_filters |
| 20260410172717_6ef25308-2370-4e33-b6ad-5f686bf8239a.sql | Financeiro, Cadastros / OS | audit_log | audit_log<br>service_orders<br>payments | - | - | - | allow_all_audit_log ON audit_log |
| 20260410174604_ff6a6010-389c-4f37-8a38-0f35be11fbf6.sql | Importa??o | import_sessions | import_sessions | - | - | - | allow_all_import_sessions ON import_sessions |
| 20260412165535_a0a80a2a-a19a-4f5e-83ff-3b7dfa7e164b.sql | Cadastros / OS | - | products<br>app_settings<br>service_orders | - | - | - | - |
| 20260412222942_b95e28f9-3e1b-408c-8a97-0f300e9d6e79.sql | Cadastros / OS | product_categories | product_categories<br>products | - | - | set_updated_at_product_categories | allow_all_product_categories ON product_categories |
| 20260413114221_27b4f182-71b6-4806-8f07-ddc4e1e7b43f.sql | Cadastros / OS | - | inventory_movements | - | - | - | - |
| 20260413164557_c4e61486-bb90-4e60-833b-849a19e63744.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260414120109_1d6f7d19-ed71-4bf7-8778-acda61114531.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260415024437_328143dc-0cd6-44bb-a456-561d591053d6.sql | Cadastros / OS | - | app_users | - | - | - | - |
| 20260415030526_dc43dc8a-8e91-4f10-b70d-81c30d85bc6e.sql | Cadastros / OS | vessel_contacts | vessel_contacts<br>service_orders | - | - | - | allow_all_vessel_contacts ON vessel_contacts |
| 20260417124206_6d2f5b3d-2617-4f26-8440-392879122618.sql | Cadastros / OS | - | app_users | - | - | - | - |
| 20260419183949_78940a7c-a2cc-486f-bd5e-a3b2d0598a95.sql | Cadastros / OS | - | - | is_admin | - | - | authenticated_all_%1$s<br>app_settings_select_auth<br>app_settings_write_admin<br>app_settings_update_admin<br>app_settings_delete_admin<br>audit_log_select_auth<br>audit_log_insert_auth<br>app_users_select_auth<br>app_users_insert_admin<br>app_users_update_admin<br>app_users_delete_admin |
| 20260420110919_3267319d-76cc-4008-a86b-3c01f2bb037d.sql | Cadastros / OS | payment_condition_presets | service_orders<br>payment_condition_presets | - | - | - | payment_condition_presets_select_auth<br>payment_condition_presets_insert_auth<br>payment_condition_presets_update_auth<br>payment_condition_presets_delete_admin |
| 20260420172126_416076db-acf2-4da6-aa90-e5e7da60f33d.sql | Cadastros / OS | - | - | - | - | - | authenticated_full_access<br>anon_read_app_settings |
| 20260421131952_e48d2328-b603-410c-b57f-22014e3b7820.sql | Cadastros / OS, Views | - | service_orders | - | - | - | Public document viewing via share_token<br>Public parts viewing via service order<br>Public services viewing via service order<br>Public company settings viewing<br>Public clients viewing via service order<br>Public vessels viewing via service order |
| 20260421133233_d9d23ec7-cd12-443d-93f9-ef91fa2821b6.sql | General | - | - | - | - | - | - |
| 20260421143927_e3b7b2cc-f9df-4b21-a7e0-7471a2a81d05.sql | Cadastros / OS | - | app_users | is_admin<br>handle_new_user | - | - | app_users_select_self_or_admin<br>app_users_insert_admin_only<br>app_users_update_admin_only<br>app_users_delete_admin_only |
| 20260421160850_2f6c8307-6e72-4478-8d2e-3c15cdbe983b.sql | Cadastros / OS | service_order_signatures | service_orders<br>service_order_signatures | - | - | - | auth_read_signatures<br>auth_update_signatures<br>anon_read_signatures_by_token<br>signatures_public_read |
| 20260421161411_f41d70d9-2353-4e54-9a07-0d327ddb3aeb.sql | General | - | - | detect_so_change_after_signature | - | trg_detect_so_change_after_signature | - |
| 20260421172230_1fd1b91a-5c9f-4276-b329-2c6aba1d2cd3.sql | General | - | audit_log | - | - | - | - |
| 20260421172306_1b76c9a7-07c2-4482-9867-24ff370ed1b5.sql | WhatsApp, Views | whatsapp_leads<br>whatsapp_messages | whatsapp_leads<br>whatsapp_messages | - | - | trg_whatsapp_leads_updated_at | Authenticated users can view leads<br>Authenticated users can insert leads<br>Authenticated users can update leads<br>Authenticated users can delete leads<br>Authenticated users can view messages<br>Authenticated users can insert messages<br>Authenticated users can update messages<br>Authenticated users can delete messages |
| 20260421173257_55d32894-41e2-4574-839b-fbcae0b14504.sql | General | - | - | - | - | - | documents_public_read<br>documents_authenticated_insert<br>documents_authenticated_update<br>documents_authenticated_delete |
| 20260421174106_66f1988c-d175-4b94-a730-683eb3ae3bc7.sql | WhatsApp | whatsapp_templates<br>whatsapp_read_state | whatsapp_templates<br>whatsapp_messages<br>whatsapp_leads<br>whatsapp_read_state | - | - | trg_whatsapp_templates_updated<br>trg_whatsapp_read_state_updated | whatsapp_templates_all_auth<br>whatsapp_read_state_self |
| 20260421175004_aa7d1c72-2d70-4d29-b019-19aa4ee39712.sql | WhatsApp, Cadastros / OS | client_whatsapp_settings | client_whatsapp_settings | - | - | update_client_whatsapp_settings_updated_at | client_whatsapp_settings_all_auth |
| 20260422103739_430bb285-c11d-4e3d-a0c6-644a315164d3.sql | WhatsApp | whatsapp_scheduled_sends | whatsapp_scheduled_sends | compute_next_run | - | trg_wss_updated_at | whatsapp_scheduled_sends_all_auth ON public.whatsapp_scheduled_sends |
| 20260422132644_21b0dbdd-c217-4615-9d4c-620edcd0d982.sql | General | collections<br>collection_contacts<br>collection_templates | collections<br>collection_contacts<br>collection_templates | - | - | collections_updated_at | authenticated_full_access |
| 20260422141525_a0f31f6f-87f4-4a37-bc84-7fbaa790eff5.sql | Cadastros / OS | - | payment_condition_presets<br>service_orders | - | - | - | - |
| 20260422150335_73878813-15a8-4d90-9330-b59bbe0cf32c.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260422155330_a263a2c2-22bc-4c12-b351-506c95fc51ec.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260422161306_62d913f0-48ab-4d95-a24f-6fcd39c10152.sql | Cadastros / OS | - | service_order_signatures | - | - | - | - |
| 20260422173113_0691c013-ee5f-416a-b69f-ac328d9cf337.sql | WhatsApp | whatsapp_blocked_numbers<br>whatsapp_quick_replies<br>whatsapp_conversation_assignments | whatsapp_blocked_numbers<br>whatsapp_quick_replies<br>whatsapp_leads<br>whatsapp_messages<br>whatsapp_conversation_assignments | - | - | - | auth_all_blocked<br>auth_all_quick<br>auth_all_assign |
| 20260422184141_1232e996-2c4c-4e78-a90a-be8b2d44b90f.sql | General | - | - | - | - | - | - |
| 20260422184349_8577bda0-bea7-46c1-8d33-84def727e5a6.sql | Cadastros / OS | agenda_tasks | agenda_tasks | - | - | update_agenda_tasks_updated_at | authenticated_all_agenda_tasks |
| 20260422190814_d85c10cc-1613-4316-8aab-e1e6938fed7e.sql | Cadastros / OS | - | app_users | - | - | - | - |
| 20260422191621_1e9b7383-4c62-45d0-b59b-0a0809e54895.sql | General | - | - | - | - | - | - |
| 20260422191930_2c815fbb-f744-4972-bb07-4fa802910c6f.sql | WhatsApp | whatsapp_send_queue | whatsapp_send_queue | - | - | trg_wa_queue_updated_at | authenticated_all_wa_queue |
| 20260422193951_c6c59866-c3d3-49c8-b396-e3f3c056344f.sql | General | - | - | wa_normalize_phone<br>wa_extract_body_text<br>wa_extract_message_type | - | - | - |
| 20260422195258_75cc1640-e29c-4131-828c-9318157b9d57.sql | General | - | - | wa_normalize_phone | - | - | - |
| 20260422212304_00af1485-5268-4c1b-9857-4685094f1019.sql | WhatsApp | - | whatsapp_messages | - | - | - | - |
| 20260422213234_85f12ad6-d5f4-4416-96ee-e3edbc1c503e.sql | Cadastros / OS | - | products | - | - | - | product_images_public_read<br>product_images_auth_insert<br>product_images_auth_update<br>product_images_auth_delete |
| 20260423141204_5b60325d-3b8f-443d-9923-d3e2d8e9a45a.sql | Cadastros / OS | - | service_order_expenses | - | - | - | expense_receipts_public_read<br>expense_receipts_auth_insert<br>expense_receipts_auth_delete |
| 20260424213018_6abbcb24-5217-4844-9a24-7eda002b114e.sql | Cadastros / OS | - | service_order_services | - | - | - | - |
| 20260424222817_bbefaaee-3df9-466c-ad35-a7a892bbe3d9.sql | Cadastros / OS | - | products | - | - | - | - |
| 20260425131630_17be375c-a12f-49c4-84c0-3f74ab872177.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260425132824_5dc1b68d-3eaa-43bb-b26f-fef73f8b88d7.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260425141256_3f88a6f0-851b-4ec9-8f5e-97116be7e918.sql | General | - | - | - | - | - | company_assets_public_read<br>company_assets_auth_write<br>company_assets_auth_update<br>company_assets_auth_delete |
| 20260427163648_2e827f51-fa0f-4999-886b-c3f354746422.sql | General | - | saved_filters | - | - | - | - |
| 20260428000000_add_warranty.sql | General | - | public | - | - | - | - |
| 20260428000001_inventory_tables.sql | General | public | public | - | - | - | - |
| 20260428000002_commissions.sql | Financeiro, Views | public | public | - | - | - | Admins can do everything on commissions<br>Users can view own commissions |
| 20260428010000_fiscal_notes.sql | Financeiro, Fiscal, Cadastros / OS, Importa??o | if<br>fiscal_notes | fiscal_notes<br>payables<br>inventory_movements | confirm_nfe_import | - | - | fiscal_notes_select<br>fiscal_notes_insert<br>fiscal_notes_update |
| 20260428020000_supplier_product_mappings.sql | Compras, Fiscal, Importa??o | supplier_product_mappings | supplier_product_mappings | confirm_nfe_import | - | - | Enable all for authenticated users |
| 20260428022454_39950c6e-57c4-405e-acc9-bf458cd2f3c2.sql | Fiscal, Cadastros / OS | fiscal_notes<br>fiscal_note_items | products<br>services<br>service_order_parts<br>service_order_services<br>fiscal_notes<br>fiscal_note_items | - | - | update_fiscal_notes_updated_at | authenticated_all_fiscal_notes<br>authenticated_all_fiscal_note_items |
| 20260428030000_price_intelligence.sql | General | product_price_history<br>price_update_suggestions | product_price_history<br>price_update_suggestions | log_product_cost_change | - | tr_log_product_cost_change | Enable all for authenticated users |
| 20260428040000_profitability_view.sql | Views | - | - | - | - | - | - |
| 20260428050000_performance_indices.sql | General | - | - | - | - | - | - |
| 20260428070000_asset_types.sql | Cadastros / OS | - | vessels | - | - | - | - |
| 20260428080000_photos.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260428120000_financial_dre.sql | Financeiro | cost_centers | cost_centers<br>payables<br>receivables | - | - | - | Enable read/write for all authenticated users |
| 20260428121826_7c58b9e4-8e9f-455c-8031-b567ff94ce2c.sql | Financeiro, Compras, Cadastros / OS | cost_centers<br>commissions<br>supplier_product_mappings<br>product_price_history<br>price_update_suggestions | vessels<br>service_orders<br>cost_centers<br>payables<br>receivables<br>commissions<br>supplier_product_mappings<br>product_price_history<br>price_update_suggestions<br>products | - | - | - | cost_centers_all_authenticated<br>commissions_admin_all<br>commissions_self_select<br>spm_all_authenticated<br>pph_all_authenticated<br>pus_all_authenticated |
| 20260428130000_reminders.sql | Cadastros / OS | - | service_orders | - | - | - | - |
| 20260430093300_add_hr_fields.sql | Cadastros / OS | - | app_users | - | - | - | - |
| 20260430120236_72f1a513-f610-45a3-879e-931cab6d65e3.sql | Financeiro, Cadastros / OS | external_quote_leads<br>external_quotes<br>external_quote_parts<br>external_quote_services | app_users<br>external_quote_leads<br>external_quotes<br>external_quote_parts<br>external_quote_services | is_external_seller<br>is_admin_or_financial<br>convert_external_quote_to_so | - | trg_eql_updated<br>trg_eq_updated<br>trg_eqp_updated<br>trg_eqs_updated | eql_select ON public.external_quote_leads FOR SELECT TO authenticated<br>eql_insert ON public.external_quote_leads FOR INSERT TO authenticated<br>eql_update ON public.external_quote_leads FOR UPDATE TO authenticated<br>eql_delete ON public.external_quote_leads FOR DELETE TO authenticated<br>eq_select ON public.external_quotes FOR SELECT TO authenticated<br>eq_insert ON public.external_quotes FOR INSERT TO authenticated<br>eq_update ON public.external_quotes FOR UPDATE TO authenticated<br>eq_delete ON public.external_quotes FOR DELETE TO authenticated<br>eqp_all ON public.external_quote_parts FOR ALL TO authenticated<br>eqs_all ON public.external_quote_services FOR ALL TO authenticated |
| 20260430120417_ea6c5188-efdf-4b21-91cf-870667212256.sql | General | - | - | convert_external_quote_to_so | - | - | - |
| 20260502221757_00b59207-9f9f-420b-9b74-bd10093b8bf7.sql | General | - | - | deduct_stock_on_os_complete | - | trg_deduct_stock_on_os_complete | - |
| 20260502222001_c7eea97d-de32-45da-ab40-7c60881ddbd4.sql | Cadastros / OS | - | service_order_services<br>service_order_parts | calc_warranty_expiry | - | trg_warranty_services<br>trg_warranty_parts | - |
| 20260502222308_70919e39-7f7f-44f2-9837-a2b55c064e3e.sql | Cadastros / OS | - | service_order_services | - | - | - | - |
| 20260502222513_1aa226ff-480a-48ff-88ab-4f30ddf9f790.sql | Cadastros / OS | service_order_photos | service_order_photos | - | - | - | so_photos_auth<br>so_photos_bucket_select<br>so_photos_bucket_insert<br>so_photos_bucket_update<br>so_photos_bucket_delete |
| 20260502222957_7c52675b-aa25-4176-8ec2-da79e4986a5a.sql | General | push_subscriptions | push_subscriptions | - | - | - | push_own |
| 20260508120000_fix_inventory_movement_type_constraint.sql | Cadastros / OS | - | inventory_movements | - | - | - | - |
| 20260508130000_register_payment_rpc.sql | RPCs / Functions | - | - | register_payment_and_update_balance | - | - | - |
| 20260508140000_cancel_so_cascade_rpc.sql | Cadastros / OS, RPCs / Functions | - | - | cancel_service_order_cascade | - | - | - |
| 20260508144510_3fd6b735-2c74-42eb-997e-f42502e592c9.sql | Cadastros / OS | - | - | cancel_service_order_cascade | - | - | - |
| 20260508144659_1edae166-a1be-4831-b078-c78dbd4980dd.sql | General | - | - | register_payment_and_update_balance | - | - | - |
| 20260508_purchase_orders.sql | Compras | purchase_orders<br>purchase_order_items | purchase_orders<br>purchase_order_items | update_updated_at_column<br>recalc_po_total<br>trg_poi_recalc_total | - | trg_po_updated_at<br>trg_poi_total | auth_all_po<br>auth_all_poi |
| 20260509120000_whatsapp_scheduled_add_manual_target.sql | WhatsApp | - | whatsapp_scheduled_sends | - | - | - | - |
| 20260509130000_api_references_zapi.sql | WhatsApp, Fiscal | api_references | api_references | - | - | - | api_references_read_auth |
| 20260509140000_whatsapp_status_scheduled.sql | WhatsApp | whatsapp_status_scheduled | whatsapp_status_scheduled | - | - | trg_whatsapp_status_scheduled_updated_at | whatsapp_status_scheduled_all_auth |

## Detected Views / RPCs / Triggers / Policies

- Views detected: vw_os_profitability
- RPC / SQL functions detected: cancel_service_order_cascade, compute_next_run, confirm_nfe_import, convert_external_quote_to_so, is_admin, is_admin_or_financial, is_external_seller, recalc_po_total, register_payment_and_update_balance, wa_extract_body_text, wa_extract_message_type, wa_normalize_phone
- Triggers detected in migrations: update_app_users_updated_at, update_marinas_updated_at, update_clients_updated_at, update_vessels_updated_at, update_products_updated_at, update_service_orders_updated_at, update_service_order_technicians_updated_at, update_service_order_parts_updated_at, update_time_entries_updated_at, update_invoices_updated_at, update_receivables_updated_at, update_payables_updated_at, update_app_settings_updated_at, set_updated_at_suppliers, set_updated_at_product_suppliers, set_updated_at_services, set_updated_at_service_order_services, set_updated_at_so_expenses, set_updated_at_product_categories, trg_detect_so_change_after_signature, trg_whatsapp_leads_updated_at, trg_whatsapp_templates_updated, trg_whatsapp_read_state_updated, update_client_whatsapp_settings_updated_at, trg_wss_updated_at, collections_updated_at, update_agenda_tasks_updated_at, trg_wa_queue_updated_at, update_fiscal_notes_updated_at, tr_log_product_cost_change, trg_eql_updated, trg_eq_updated, trg_eqp_updated, trg_eqs_updated, trg_deduct_stock_on_os_complete, trg_warranty_services, trg_warranty_parts, trg_po_updated_at, trg_poi_total, trg_whatsapp_status_scheduled_updated_at
- Policy definitions detected across migrations: 130

## Backup Coverage Matrix

| Table | In backup | In config | In types.ts | In migrations | Observation |
|---|---:|---:|---:|---:|---|
| app_settings | yes | no | yes | yes | covered by schema/types and migration history |
| app_users | yes | no | yes | yes | covered by schema/types and migration history |
| audit_log | yes | no | yes | yes | covered by schema/types and migration history |
| clients | yes | yes | yes | yes | covered by migration-config; natural duplicate keys exist in email and cpf_cnpj; covered by schema/types and migration history |
| collections | yes | no | yes | yes | covered by schema/types and migration history |
| external_quote_leads | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| external_quote_parts | yes | no | yes | yes | covered by schema/types and migration history |
| external_quote_services | yes | no | yes | yes | covered by schema/types and migration history |
| external_quotes | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| financial_categories | yes | no | yes | yes | covered by schema/types and migration history |
| inventory_movements | yes | no | yes | yes | covered by schema/types and migration history |
| marinas | yes | no | yes | yes | covered by schema/types and migration history |
| payables | yes | no | yes | yes | covered by schema/types and migration history |
| payment_condition_presets | yes | no | yes | yes | covered by schema/types and migration history |
| product_categories | yes | no | yes | yes | covered by schema/types and migration history |
| products | yes | no | yes | yes | covered by schema/types and migration history |
| service_order_parts | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| service_order_services | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| service_order_technicians | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| service_orders | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| services | yes | yes | yes | yes | covered by migration-config; natural duplicate key in backup uses service_name; config still tracks `name` only; covered by schema/types and migration history |
| suppliers | yes | yes | yes | yes | covered by migration-config; covered by schema/types and migration history |
| vessels | yes | no | yes | yes | covered by schema/types and migration history |

## Repo-only Tables Not in Lovable Backup

- agenda_tasks
- bank_transactions
- card_installment_fees
- client_whatsapp_settings
- collection_contacts
- collection_templates
- commissions
- cost_centers
- exchange_rates
- fiscal_note_items
- fiscal_notes
- import_sessions
- invoices
- payments
- price_update_suggestions
- product_price_history
- product_suppliers
- purchase_order_items
- purchase_orders
- push_subscriptions
- receivables
- saved_filters
- service_order_expenses
- service_order_photos
- service_order_signatures
- supplier_product_mappings
- time_entries
- vessel_contacts
- whatsapp_blocked_numbers
- whatsapp_conversation_assignments
- whatsapp_leads
- whatsapp_messages
- whatsapp_quick_replies
- whatsapp_read_state
- whatsapp_scheduled_sends
- whatsapp_send_queue
- whatsapp_templates

## Backup Tables With Gaps

- none

## Risks and Gaps

- Several migrations combine create-table, policy, and function changes in the same file, so staging application order matters.
- `supabase/config.toml` still points at `zssewfqhmrlagqbfqsmb`; the readiness plan must avoid linking staging to that project by accident.
- The repo has more tables in types.ts than the Lovable backup exports; staging import must be selective and validated.
- Current backup analysis shows duplicate natural keys in `clients` and `services`, so deduplication rules must be explicit before any import.
- Edge Functions include webhook- and queue-driven flows; staging should start with external integrations disabled or pointed to test endpoints.

## Manual Validation Still Needed

- Confirm the new Supabase staging project ref before any CLI link or migration run.
- Verify which tables are expected to be empty versus seeded after schema application.
- Compare live staging counts against the backup using read-only probes before import.
- Re-generate types after staging schema application to confirm the generated client stays aligned.
