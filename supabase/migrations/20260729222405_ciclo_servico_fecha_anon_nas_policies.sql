-- FURO FECHADO: as policies do Ciclo do Serviço nasceram sem cláusula TO, o que
-- as coloca no role `public` — ou seja, valem também para `anon`. Como
-- is_external_seller(null) devolve FALSE, a condição
-- `not is_external_seller(auth.uid())` era VERDADEIRA para anônimo: qualquer um
-- com a chave pública (que está no bundle do frontend por natureza) lia e
-- escrevia passos, templates, casos e as revisões de IA.
--
-- Reproduzido em Postgres 17 de teste antes da correção: anon leu 2 passos e
-- inseriu uma linha em work_stop_reasons. Depois da correção: permission denied
-- nas duas operações, com `authenticated` seguindo normal.
--
-- Correção: toda policy passa a valer somente para `authenticated`, no mesmo
-- padrão das migrations 20260728231611 e 20260729144824.
--
-- Lição para as próximas: `create policy ... using (...)` SEM `to authenticated`
-- não fecha anon — a condição precisa ser falsa para auth.uid() nulo, e as
-- funções de cargo deste projeto devolvem false para nulo.

-- ── work_stop_reasons ────────────────────────────────────────────────────────
drop policy if exists work_stop_reasons_read on public.work_stop_reasons;
drop policy if exists work_stop_reasons_write on public.work_stop_reasons;

create policy work_stop_reasons_read on public.work_stop_reasons
  for select to authenticated using (true);
-- Mexer na lista muda o significado de todo o histórico de paradas: só equipe interna.
create policy work_stop_reasons_write on public.work_stop_reasons
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── service_step_templates ───────────────────────────────────────────────────
drop policy if exists service_step_templates_all on public.service_step_templates;
create policy service_step_templates_all on public.service_step_templates
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── service_order_steps ──────────────────────────────────────────────────────
drop policy if exists service_order_steps_all on public.service_order_steps;
create policy service_order_steps_all on public.service_order_steps
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── service_cases ────────────────────────────────────────────────────────────
drop policy if exists service_cases_all on public.service_cases;
create policy service_cases_all on public.service_cases
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ── ai_suggestion_reviews ────────────────────────────────────────────────────
drop policy if exists ai_suggestion_reviews_all on public.ai_suggestion_reviews;
create policy ai_suggestion_reviews_all on public.ai_suggestion_reviews
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- Cinto e suspensório: mesmo com policy correta, anon não precisa de grant algum
-- nestas tabelas. Se a RLS falhar por engano futuro, o grant não deixa passar.
revoke all on public.service_order_steps from anon;
revoke all on public.service_step_templates from anon;
revoke all on public.service_cases from anon;
revoke all on public.ai_suggestion_reviews from anon;
revoke all on public.work_stop_reasons from anon;
