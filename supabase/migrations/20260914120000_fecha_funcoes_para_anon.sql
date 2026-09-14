-- Convergência repositório ↔ produção, parte 2 (MF-AUD-058 / MF-AUD-025). Muda privilégios de
-- execução, por isso foi aplicada pelo PRÓPRIO DONO em 14/09/2026 (o classificador da sessão
-- barra a IA de gravar/aplicar GRANT e REVOKE), com prova: só share_token_da_requisicao()
-- continua executável por anon.
--
-- 36 funções do schema public estão executáveis por anon sem motivo. Quatro delas (fios
-- soltos: record_conversation_loop ×2, touch_open_loop, refresh_entity_open_loops,
-- backfill_message_identity) a 20260727200000_open_loops_fixes fechou e uma migration perdida
-- do mesmo dia reabriu ao recriá-las; as outras nunca foram fechadas.
--
-- Conferido em 14/09/2026: nenhuma página pública chama RPC (src/pages/Public*); no app só
-- use-agenda.ts chama get_agenda_conflicts (autenticado); as edges usam service_role. Por isso
-- authenticated e service_role recebem grant nominal — quem perde o EXECUTE herdado de PUBLIC
-- o recebe de volta explicitamente (lição do lev-31: revogar só de anon não fecha o que veio
-- por PUBLIC). share_token_da_requisicao() fica aberta de propósito: as políticas anon do
-- portal dependem dela.
-- Funções de trigger perdem EXECUTE de PUBLIC e anon como no precedente de 24/07
-- (stock_bom_security_hardening): trigger dispara sem checar EXECUTE de quem grava.
--
-- PROVA depois de aplicar:
--   select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and has_function_privilege('anon', p.oid, 'EXECUTE')
--     and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e');
--   -- esperado: só share_token_da_requisicao

-- ── funções chamáveis: fecham para PUBLIC/anon, abrem nominalmente ────────────
revoke execute on function public.backfill_message_identity(integer) from public, anon;
grant execute on function public.backfill_message_identity(integer) to authenticated, service_role;
revoke execute on function public.bi_margin_by_category(date) from public, anon;
grant execute on function public.bi_margin_by_category(date) to authenticated, service_role;
revoke execute on function public.bi_revenue_by_brand(date, text) from public, anon;
grant execute on function public.bi_revenue_by_brand(date, text) to authenticated, service_role;
revoke execute on function public.bi_top_clients(date, integer) from public, anon;
grant execute on function public.bi_top_clients(date, integer) to authenticated, service_role;
revoke execute on function public.compute_next_run(timestamptz, text, integer[], integer) from public, anon;
grant execute on function public.compute_next_run(timestamptz, text, integer[], integer) to authenticated, service_role;
revoke execute on function public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid) from public, anon;
grant execute on function public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid) to authenticated, service_role;
revoke execute on function public.get_entity_open_loops(text, uuid, integer) from public, anon;
grant execute on function public.get_entity_open_loops(text, uuid, integer) to authenticated, service_role;
revoke execute on function public.get_open_loops(text, integer) from public, anon;
grant execute on function public.get_open_loops(text, integer) to authenticated, service_role;
revoke execute on function public.normalize_alias(text) from public, anon;
grant execute on function public.normalize_alias(text) to authenticated, service_role;
revoke execute on function public.normalize_product_text(text) from public, anon;
grant execute on function public.normalize_product_text(text) to authenticated, service_role;
revoke execute on function public.pode_ver_folha(uuid) from public, anon;
grant execute on function public.pode_ver_folha(uuid) to authenticated, service_role;
revoke execute on function public.recalc_po_total(uuid) from public, anon;
grant execute on function public.recalc_po_total(uuid) to authenticated, service_role;
revoke execute on function public.record_conversation_loop(text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid) from public, anon;
grant execute on function public.record_conversation_loop(text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid) to authenticated, service_role;
revoke execute on function public.record_conversation_loop(text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid, text) from public, anon;
grant execute on function public.record_conversation_loop(text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid, text) to authenticated, service_role;
revoke execute on function public.refresh_entity_open_loops() from public, anon;
grant execute on function public.refresh_entity_open_loops() to authenticated, service_role;
revoke execute on function public.resolve_contact_identity(text) from public, anon;
grant execute on function public.resolve_contact_identity(text) to authenticated, service_role;
revoke execute on function public.search_products_trgm(text, integer) from public, anon;
grant execute on function public.search_products_trgm(text, integer) to authenticated, service_role;
revoke execute on function public.touch_open_loop(uuid, text, timestamptz, uuid) from public, anon;
grant execute on function public.touch_open_loop(uuid, text, timestamptz, uuid) to authenticated, service_role;
revoke execute on function public.wa_extract_body_text(jsonb) from public, anon;
grant execute on function public.wa_extract_body_text(jsonb) to authenticated, service_role;
revoke execute on function public.wa_extract_message_type(jsonb) from public, anon;
grant execute on function public.wa_extract_message_type(jsonb) to authenticated, service_role;
revoke execute on function public.wa_normalize_phone(text) from public, anon;
grant execute on function public.wa_normalize_phone(text) to authenticated, service_role;
revoke execute on function public.whatsapp_pending_inbox(timestamptz, integer) from public, anon;
grant execute on function public.whatsapp_pending_inbox(timestamptz, integer) to authenticated, service_role;

-- ── funções de trigger: ninguém as chama; disparam sem checar EXECUTE ─────────
revoke all on function public.calc_shift_duration() from public, anon;
revoke all on function public.calc_warranty_expiry() from public, anon;
revoke all on function public.deduct_stock_on_os_complete() from public, anon;
revoke all on function public.detect_so_change_after_signature() from public, anon;
revoke all on function public.log_product_cost_change() from public, anon;
revoke all on function public.set_ai_agent_memory_updated_at() from public, anon;
revoke all on function public.set_ai_agent_tasks_updated_at() from public, anon;
revoke all on function public.set_ai_inbound_sessions_updated_at() from public, anon;
revoke all on function public.set_ai_workflows_updated_at() from public, anon;
revoke all on function public.set_updated_at_now() from public, anon;
revoke all on function public.touch_fiscal_emission_draft() from public, anon;
revoke all on function public.touch_updated_at() from public, anon;
revoke all on function public.trg_poi_recalc_total() from public, anon;
revoke all on function public.update_updated_at_column() from public, anon;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260914120000', 'fecha_funcoes_para_anon')
on conflict (version) do nothing;
