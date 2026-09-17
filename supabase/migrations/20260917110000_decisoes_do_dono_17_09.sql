-- Decisões do dono em 17/09/2026 (Diário de Bordo, D1–D35), a parte que vive no banco.
-- Cada bloco cita a decisão. Tudo idempotente: rodar duas vezes não muda nada.

-- ── D1: propostas de lançamento geradas por cron, 06:00 de Brasília (09:00 UTC) ─────────
-- Só GERA (action generate): aprovar continua sendo clique do gestor, e as regras com
-- autonomia só lançam sozinhas até o limite de lote (D2, no código do finance-review).
select cron.unschedule('finance-review-generate')
where exists (select 1 from cron.job where jobname = 'finance-review-generate');
select cron.schedule(
  'finance-review-generate',
  '0 9 * * *',
  $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/finance-review',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{"action": "generate"}'::jsonb,
    timeout_milliseconds := 120000
  );
  $cron$
);

-- ── D3: farmácia = retirada de sócio (não operacional), como sugestão na caixa de entrada ──
insert into public.financial_categories (name, type, dre_group, active, description)
select 'Retirada de sócio', 'payable', 'nao_operacional', true,
       'Gasto pessoal pago pela conta da empresa (farmácia, mercado, etc.). Não entra no resultado operacional.'
where not exists (select 1 from public.financial_categories where name = 'Retirada de sócio' and type = 'payable');

-- Já existia uma regra "farma" proposta pelo sugerir_regras (índice único
-- finance_rules_uma_por_alvo em match_type, lower(match_value), direction): em vez de
-- inserir por cima, a regra existente é REAPONTADA para a categoria decidida e ativada.
insert into public.finance_rules (match_type, match_value, direction, set_category, set_dre_group, autonomy, origin, status, reasoning, note)
values
  ('text', 'FARMA',    'debit', 'Retirada de sócio', 'nao_operacional', 'suggest', 'user', 'active',
   'D3 (17/09/2026): farmácia e drogaria são gasto pessoal, salvo medicamento de bordo ou EPI — por isso só sugere.',
   'Decisão do dono em 17/09/2026'),
  ('text', 'DROGARIA', 'debit', 'Retirada de sócio', 'nao_operacional', 'suggest', 'user', 'active',
   'D3 (17/09/2026): farmácia e drogaria são gasto pessoal, salvo medicamento de bordo ou EPI — por isso só sugere.',
   'Decisão do dono em 17/09/2026')
on conflict (match_type, lower(match_value), direction) where status in ('active', 'proposed') do update
  set set_category  = excluded.set_category,
      set_dre_group = excluded.set_dre_group,
      autonomy      = 'suggest',
      status        = 'active',
      reasoning     = excluded.reasoning,
      note          = excluded.note,
      updated_at    = now();

-- ── D9: uma chave de km só (travel_km_rate). As duas órfãs com 3,50 saem. ───────────────
delete from public.app_settings where key in ('cost_per_km', 'travel_cost_per_km');

-- ── D21: piso de materialidade da cobrança ───────────────────────────────────────────────
insert into public.app_settings (key, value, description)
values ('collection_min_amount', '200',
        'Abaixo deste valor (R$) a IA e os lembretes automáticos NÃO cobram por WhatsApp; o recebível só fica listado.')
on conflict (key) do nothing;

-- ── D18: perfil enxuto de tools do agente ────────────────────────────────────────────────
-- ai_tool_profile = 'operacao' liga o corte; qualquer outro valor devolve todas as tools.
-- A lista = tools usadas nos últimos 60 dias (ai_operator_audit) + as essenciais do dia a
-- dia. Tools de risco alto entram sempre (o sino precisa encontrá-las); tool citada pelo
-- nome no pedido entra também. Editar a lista aqui muda o agente em até 5 minutos.
insert into public.app_settings (key, value, description)
values ('ai_tool_profile', 'operacao',
        'Perfil de tools do agente: operacao (lista enxuta em ai_tool_profile_operacao) ou completo.')
on conflict (key) do update set value = excluded.value;

insert into public.app_settings (key, value, description)
values ('ai_tool_profile_operacao', '["search_products","remove_service_order_item","get_service_order","add_service_order_item","create_product","get_product_price_history","add_service_to_order","add_material_to_order","edit_service_order_item","search_clients","search_vessels","size_dc_cable","search_suppliers","list_service_orders","create_quote_from_items","search_products_batch","search_services","update_product","record_survey_answer","assess_survey_confidence","survey_material_list","create_quote_request","create_service_order","close_service_survey","create_payable","create_vessel","sugerir_conciliacao","schedule_self_reminder","list_unanswered_messages","listar_categorias_financeiras","set_service_order_charges","get_client_360","present_options","suggest_suppliers","get_os_receivables","log_service_order_progress","list_pending_pos","read_supplier_messages","update_vessel","identify_contact","listar_transacoes_pendentes","update_client","list_reference_data","check_needs_survey","create_client","get_os_profitability","list_overdue_receivables","get_service_order_route","start_service_survey","get_delinquency_plan","apply_service_order_discount","create_supplier","get_route_drafting_context","get_client_history","list_low_stock","get_purchase_needs","update_service_order_status","update_service_order_notes","criar_missao_acompanhamento","listar_missoes_acompanhamento","cancelar_missao_acompanhamento","get_situation_overview","my_agenda","list_tasks","create_task","update_task","complete_task","list_team_agenda","schedule_service_order","check_technician_availability","get_period_summary","resultado_do_periodo","get_top_clients","list_payables_due","list_pending_collections","listar_propostas_de_lancamento","recusar_propostas_de_lancamento","reclassificar_propostas_de_lancamento","classificar_propostas_com_ia","sugerir_regras_financeiras","desfazer_propostas_ignoradas","listar_regras_financeiras","criar_regra_financeira","listar_favorecidos","cadastrar_favorecido","analisar_extrato_e_propor_lancamentos","update_quote_status","apply_quote_price","duplicate_service_order","log_service_order_hours","registrar_jornada","minhas_horas","fechar_jornada","apurar_pagamento","preview_fiscal_note","preview_fiscal_service_note","list_fiscal_documents","register_stock_entry","record_quote_response","get_quote_comparison","get_supplier_360","get_vessel_history","generate_service_order_route","save_drafted_route_steps","add_service_order_step","start_service_order_step","complete_service_order_step","skip_service_order_step","block_service_order_step","check_in_service_order","check_out_service_order","attach_photo_to_service_order","optimize_text","list_technicians","get_service_order_margin","create_receivable","update_payable","update_receivable","get_open_loops","list_scheduled_whatsapp","cancel_scheduled_whatsapp","mute_contact","add_kit_to_order","add_service_order_expense"]',
        'Tools que entram no turno quando ai_tool_profile = operacao (mais as de risco alto e as citadas pelo nome).')
on conflict (key) do update set value = excluded.value;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260917110000', 'decisoes_do_dono_17_09')
on conflict do nothing;
