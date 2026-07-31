-- ⚠ APLICADA EM PRODUÇÃO SOMENTE EM 31/07/2026, e com uma diferença.
--
-- Este arquivo foi commitado em 29/07 (caf5246) mas NUNCA chegou ao banco —
-- descoberto ao conciliar pg_policies com o repositório: só 8 policies tinham
-- regra de cargo, e as 8 eram de outra frente. As tabelas internas seguiam
-- abertas a vendedor externo por dois dias.
--
-- Ao aplicar, os 5 ALTER de purchase_orders, purchase_order_items,
-- quote_requests, quote_request_items e quote_responses foram OMITIDOS: aquelas
-- policies não existem mais. A frente de Compras (rls_compras_por_cargo, 30/07)
-- as substituiu por policies granulares por comando, já com regra de cargo em
-- USING e WITH CHECK — verificado uma a uma. Mantê-los faria a migration inteira
-- falhar, porque ALTER POLICY exige que o nome exista.
--
-- Efeito medido: policies com regra de cargo passaram de 8 para 33.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- Restringe as políticas "permitir tudo" (RLS Policy Always True) de 19 tabelas
-- INTERNAS ao perfil de EQUIPE, fechando o risco latente do recurso de vendedor
-- externo (role external_seller) ANTES de o primeiro ser cadastrado.
--
-- Contexto verificado (pg_policies + app_users + código):
--   * As 19 tabelas guardam dados internos (custos, compras, WhatsApp, notas
--     fiscais, preços, cobrança) — NENHUMA faz parte do fluxo de orçamento
--     externo (external_quotes/parts/services/leads). Um external_seller não
--     precisa de nenhuma delas.
--   * Todas as políticas afetadas são do papel `authenticated` (zero `anon`).
--   * Hoje existem 5 usuários, TODOS staff (admin/technician/financial) e ZERO
--     external_seller. Logo o predicado abaixo é sempre verdadeiro para eles →
--     COMPORTAMENTO IDÊNTICO ao atual. Um external_seller (0 hoje) já nasceria
--     barrado destas tabelas.
--
-- Predicado: NOT public.is_external_seller(auth.uid())
--   * is_external_seller é STABLE SECURITY DEFINER e lê app_users por fora da RLS
--     → sem recursão de política. authenticated tem EXECUTE nela (mantido na
--     migration de revoke). O (select ...) força avaliação única por query
--     (InitPlan), não por linha — também alivia o advisor de performance.
--   * Restrito ao papel `authenticated`, então anon nunca aciona estas políticas.
--
-- Reversível: reabrir = ALTER ... USING (true) WITH CHECK (true) (ver rodapé).
-- Idempotente: reaplicar apenas re-define o mesmo predicado.
-- Aplicar por SQL Editor + SMOKE TEST no app (logar e abrir: Compras, Centros de
-- Custo, WhatsApp, Notas Fiscais, Cobrança) — a equipe deve manter acesso total.

-- ── ai_comms_log ────────────────────────────────────────────────────────────
alter policy authenticated_all_ai_comms_log on public.ai_comms_log
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── ai_message_feedback ─────────────────────────────────────────────────────
alter policy authenticated_all_ai_message_feedback on public.ai_message_feedback
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── api_references (SELECT) ─────────────────────────────────────────────────
alter policy api_references_read_auth on public.api_references
  using (not (select public.is_external_seller(auth.uid())));

-- ── collection_contacts ─────────────────────────────────────────────────────
alter policy authenticated_full_access on public.collection_contacts
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── collection_templates ────────────────────────────────────────────────────
alter policy authenticated_full_access on public.collection_templates
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── collections ─────────────────────────────────────────────────────────────
alter policy authenticated_full_access on public.collections
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── cost_centers (duas políticas duplicadas — constranjo ambas) ─────────────
alter policy "Enable read/write for all authenticated users" on public.cost_centers
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy cost_centers_all_authenticated on public.cost_centers
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── fiscal_notes (constranjo as 4: a ALL "auth not null" + insert/select/update) ─
alter policy authenticated_all_fiscal_notes on public.fiscal_notes
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy fiscal_notes_insert on public.fiscal_notes
  with check (not (select public.is_external_seller(auth.uid())));
alter policy fiscal_notes_select on public.fiscal_notes
  using (not (select public.is_external_seller(auth.uid())));
alter policy fiscal_notes_update on public.fiscal_notes
  using (not (select public.is_external_seller(auth.uid())));

-- ── price_update_suggestions (duas duplicadas) ──────────────────────────────
alter policy "Enable all for authenticated users" on public.price_update_suggestions
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy pus_all_authenticated on public.price_update_suggestions
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── product_aliases ─────────────────────────────────────────────────────────
alter policy authenticated_all_product_aliases on public.product_aliases
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── product_price_history (duas duplicadas) ─────────────────────────────────
alter policy "Enable all for authenticated users" on public.product_price_history
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy pph_all_authenticated on public.product_price_history
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── purchase_order_items ────────────────────────────────────────────────────
alter policy auth_all_poi on public.purchase_order_items
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── purchase_orders ─────────────────────────────────────────────────────────
alter policy auth_all_po on public.purchase_orders
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── quote_request_items ─────────────────────────────────────────────────────
alter policy authenticated_all_quote_request_items on public.quote_request_items
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── quote_requests ──────────────────────────────────────────────────────────
alter policy authenticated_all_quote_requests on public.quote_requests
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── quote_responses ─────────────────────────────────────────────────────────
alter policy authenticated_all_quote_responses on public.quote_responses
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── supplier_product_mappings (duas duplicadas) ─────────────────────────────
alter policy "Enable all for authenticated users" on public.supplier_product_mappings
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy spm_all_authenticated on public.supplier_product_mappings
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── whatsapp_leads (SELECT/INSERT/UPDATE/DELETE separados) ───────────────────
alter policy "Authenticated users can view leads" on public.whatsapp_leads
  using (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can insert leads" on public.whatsapp_leads
  with check (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can update leads" on public.whatsapp_leads
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can delete leads" on public.whatsapp_leads
  using (not (select public.is_external_seller(auth.uid())));

-- ── whatsapp_messages (SELECT/INSERT/UPDATE/DELETE separados) ────────────────
alter policy "Authenticated users can view messages" on public.whatsapp_messages
  using (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can insert messages" on public.whatsapp_messages
  with check (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can update messages" on public.whatsapp_messages
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));
alter policy "Authenticated users can delete messages" on public.whatsapp_messages
  using (not (select public.is_external_seller(auth.uid())));

-- ── whatsapp_status_scheduled ───────────────────────────────────────────────
alter policy whatsapp_status_scheduled_all_auth on public.whatsapp_status_scheduled
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (reabrir tudo), se necessário — reverter cada policy para:
--   using (true) with check (true)   [ALL/UPDATE]
--   using (true)                     [SELECT/DELETE]
--   with check (true)                [INSERT]
-- (fiscal_notes.authenticated_all_fiscal_notes volta a: using/with check (auth.uid() is not null))
