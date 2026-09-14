# Reconciliação do histórico de migrations — 2026-09-14

Arquivos locais sem registro: **24** — total: 11 · parcial: 3 · nenhum: 0 · sem evidência: 6
Versões remotas sem arquivo: **0** (0 duplicatas de arquivos existentes)

## nenhum (0)


## parcial (3)

- `20260727200001_open_loops_fixes.sql` — 7/11
    - ✔ função refresh_entity_open_loops
    - ✔ índice agenda_suggestions_open_loop
    - ✔ coluna agenda_suggestions.open_loop_id
    - ✘ anon sem EXECUTE em refresh_entity_open_loops
    - ✘ anon sem EXECUTE em touch_open_loop
    - ✘ anon sem EXECUTE em record_conversation_loop
    - ✘ anon sem EXECUTE em backfill_message_identity
    - ✔ security_invoker em erp_open_loop_facts
    - ✔ security_invoker em unidentified_contacts
    - ✔ anon sem privilégio em erp_open_loop_facts
    - ✔ anon sem privilégio em unidentified_contacts
    - ○ dado: update entity_open_loops
    - ○ dado: update entity_open_loops
    - ○ dado: update entity_open_loops
    - ○ dado: update entity_open_loops
    - ○ dado: update entity_open_loops
- `20260730020000_ciclo_servico_levantamento.sql` — 17/18
    - ✔ tabela service_survey_templates
    - ✔ tabela service_surveys
    - ✔ tabela service_survey_answers
    - ✔ função should_survey_service
    - ✔ função estimate_from_cases
    - ✔ índice service_survey_templates_service
    - ✔ índice service_surveys_os
    - ✔ índice service_surveys_status
    - ✔ índice service_survey_answers_survey
    - ✘ trigger service_survey_templates|set_updated_at_service_survey_templates
    - ✔ trigger service_surveys|set_updated_at_service_surveys
    - ✔ coluna service_orders.survey_id
    - ✔ constraint service_orders_estimate_confidence_check
    - ✔ rls service_survey_templates
    - ✔ rls service_surveys
    - ✔ rls service_survey_answers
    - ✔ anon sem EXECUTE em should_survey_service
    - ✔ anon sem EXECUTE em estimate_from_cases
- `20260731040000_ciclo_servico_composicao_de_roteiro.sql` — 11/13
    - ✔ tabela service_step_blocks
    - ✔ função classify_service_text
    - ✔ função compose_route_for_service
    - ✔ índice services_classificacao
    - ✔ índice step_blocks_sistema
    - ✔ índice step_blocks_verbo
    - ✔ trigger service_step_blocks|set_updated_at_service_step_blocks
    - ✔ coluna services.service_verb
    - ✘ constraint services_verb_check
    - ✘ constraint services_system_check
    - ✔ rls service_step_blocks
    - ✔ anon sem EXECUTE em classify_service_text
    - ✔ anon sem EXECUTE em compose_route_for_service
    - ○ dado: update services

## sem_evidencia (6)

- `20260515154305_181f62a3-65ed-4079-9d89-f0546223e92c.sql` — 0/0
- `20260722220000_log_app_error_service_role.sql` — 0/0
- `20260728010000_search_path_security_definer.sql` — 0/0
- `20260728015000_rls_anon_fase1_fecha_assinaturas_e_presets.sql` — 0/0
- `20260729211000_dedupe_extrato_fatura_cartao_sinonimos.sql` — 0/0
- `20260730120000_rls_compras_por_cargo.sql` — 0/0

## so_dados (4)

- `20260730010000_preenche_contraparte_pelo_cadastro.sql` — 0/0
    - ○ dado: update bank_transactions
    - ○ dado: update bank_transactions
    - ○ dado: update bank_transactions
- `20260731030000_categoria_comissoes.sql` — 0/0
    - ○ dado: insert into financial_categories
- `20260804010000_credito_em_cartao_nunca_e_receita.sql` — 0/0
    - ○ dado: update bank_transactions
- `20260804020000_pix_no_credito_nao_e_receita.sql` — 0/0
    - ○ dado: update bank_transactions

## total (11)

- `20260724180001_fiscal_emission_drafts.sql` — 12/12
- `20260727120001_bank_transactions_dedupe_enriquecimento.sql` — 4/4
- `20260727120002_contact_identity.sql` — 7/7
- `20260727120003_get_promo_candidates_rpc.sql` — 2/2
- `20260727180001_balance_due_on_completion.sql` — 3/3
- `20260727180002_entity_open_loops.sql` — 10/10
- `20260727200000_balance_reminders_cron.sql` — 1/1
- `20260731020001_ciclo_servico_materiais_e_margem.sql` — 8/8
- `20260803120001_rpc_get_os_purchase_needs.sql` — 2/2
- `20260803140001_envio_real_de_cotacao.sql` — 5/5
- `20260805100001_separa_material_de_mao_de_obra.sql` — 7/7

## Versões remotas sem arquivo (stubs)

