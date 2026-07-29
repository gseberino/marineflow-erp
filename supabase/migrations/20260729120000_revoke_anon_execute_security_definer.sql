-- Remove o EXECUTE de anon/PUBLIC nas 18 funções SECURITY DEFINER hoje chamáveis
-- com a chave pública (advisor "Public Can Execute SECURITY DEFINER Function").
--
-- Estas funções rodam com o privilégio do dono. Deixá-las executáveis por `anon`
-- (sem login) é a superfície voltada para a internet — um chamador com só a chave
-- pública poderia invocá-las. O app legítimo nunca precisa delas via anon.
--
-- Classificação (conferida em pg_proc + grep no frontend + pg_policies):
--   A) 7 TRIGGERS: retornam `trigger`, não podem ser chamadas via API; o gatilho
--      dispara independente de GRANT. Revogar de anon E authenticated é seguro.
--   B) 8 RPCs: chamadas pelo frontend logado (authenticated) ou por edge
--      (service_role). Revoga anon; mantém authenticated + service_role.
--   C) 3 helpers de RLS: usadas dentro das políticas para `authenticated`.
--      Verificado que NENHUMA política de `anon` as referencia — revogar anon é seguro.
--
-- service_role (edge functions) mantém EXECUTE em tudo. Idempotente (REVOKE de
-- privilégio inexistente é no-op). Não altera corpo nem comportamento do app logado.

-- ── Grupo A — triggers (revoga PUBLIC, anon, authenticated) ──────────────────
revoke execute on function public.handle_new_user()                      from public, anon, authenticated;
revoke execute on function public.handle_quote_deposit_payment()         from public, anon, authenticated;
revoke execute on function public.reverse_nfe_settlement_on_cancel()     from public, anon, authenticated;
revoke execute on function public.sync_balance_due_on_completion()       from public, anon, authenticated;
revoke execute on function public.sync_collection_from_receivable()      from public, anon, authenticated;
revoke execute on function public.sync_commission_on_so_complete()       from public, anon, authenticated;
revoke execute on function public.sync_service_order_payment_status()    from public, anon, authenticated;

-- ── Grupo B — RPCs com login (revoga PUBLIC, anon; mantém authenticated) ─────
revoke execute on function public.cancel_service_order_cascade(uuid, text)                                              from public, anon;
revoke execute on function public.convert_external_quote_to_so(uuid)                                                    from public, anon;
revoke execute on function public.next_document_number()                                                               from public, anon;
revoke execute on function public.receive_po(uuid, jsonb, integer)                                                     from public, anon;
revoke execute on function public.register_deposit_and_convert(uuid, numeric, date, text, numeric, text, jsonb, boolean) from public, anon;
revoke execute on function public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text) from public, anon;
revoke execute on function public.recalc_so_totals(uuid)                                                               from public, anon;
revoke execute on function public.remember_reconciliation(text, uuid, text)                                            from public, anon;

-- ── Grupo C — helpers de RLS (revoga PUBLIC, anon; mantém authenticated) ─────
revoke execute on function public.is_admin(uuid)               from public, anon;
revoke execute on function public.is_admin_or_financial(uuid)  from public, anon;
revoke execute on function public.is_external_seller(uuid)     from public, anon;
