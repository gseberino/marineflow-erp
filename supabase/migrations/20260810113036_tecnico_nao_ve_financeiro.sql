-- MF-AUD-020 — decisão #3 do dono (09/08/2026): o cargo técnico não enxerga nada
-- financeiro. Vale nos dois planos; este arquivo é o plano do BANCO. O plano das tools
-- do agente foi a T1.5.
--
-- O QUE HAVIA: as cinco tabelas do dinheiro tinham política única
-- `FOR ALL TO authenticated USING (auth.uid() IS NOT NULL)`. Qualquer usuário logado —
-- inclusive técnico — lia, alterava e apagava o financeiro inteiro com o próprio JWT,
-- por chamada REST direta. A restrição existia apenas no ProtectedRoute do frontend, que
-- é navegação, não controle de acesso: quem tem login tem a chave da API.
--
-- ESCOPO: só o técnico é barrado. admin, financial, seller e external_seller continuam
-- exatamente como estavam — este arquivo não é uma revisão do modelo de acesso, é o
-- cumprimento de uma decisão específica.
--
-- payables NÃO entra aqui: já foi tratada na T1.4 (MF-AUD-023), e o predicado de
-- categoria sensível daquela migration seria sobrescrito se eu reescrevesse as políticas.
-- Ela ganha o predicado de técnico por ALTER, preservando o que já existe.

-- ── Helper de cargo, espelhando is_external_seller ──────────────────────────────
-- STABLE SECURITY DEFINER: roda dentro da política e precisa ler app_users por fora da
-- RLS, senão a política de app_users recursaria sobre si mesma.
CREATE OR REPLACE FUNCTION public.is_technician(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_users
    WHERE id = _user_id AND role = 'technician' AND active = true
  );
$$;

COMMENT ON FUNCTION public.is_technician(uuid) IS
  'Verdadeiro para usuário ativo de cargo técnico. Usada nas políticas do financeiro (decisão do dono, 09/08/2026).';

-- Função nova nasce com EXECUTE para PUBLIC — fechar antes que vire superfície (MF-AUD-025).
REVOKE EXECUTE ON FUNCTION public.is_technician(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_technician(uuid) TO authenticated, service_role;

-- ── As quatro tabelas com política única FOR ALL ────────────────────────────────
-- ALTER preserva o nome e o comando da política; só aperta o predicado.
ALTER POLICY authenticated_all_payments ON public.payments
  USING      (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()))
  WITH CHECK (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()));

ALTER POLICY authenticated_all_receivables ON public.receivables
  USING      (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()))
  WITH CHECK (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()));

ALTER POLICY authenticated_all_invoices ON public.invoices
  USING      (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()))
  WITH CHECK (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()));

ALTER POLICY authenticated_all_bank_transactions ON public.bank_transactions
  USING      (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()))
  WITH CHECK (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()));

-- ── payables: acrescenta o técnico SEM perder a regra de categoria sensível ──────
ALTER POLICY payables_select ON public.payables
  USING (
    auth.uid() IS NOT NULL
    AND NOT public.is_technician(auth.uid())
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );

ALTER POLICY payables_insert ON public.payables
  WITH CHECK (auth.uid() IS NOT NULL AND NOT public.is_technician(auth.uid()));

ALTER POLICY payables_update ON public.payables
  USING (
    auth.uid() IS NOT NULL
    AND NOT public.is_technician(auth.uid())
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  )
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND NOT public.is_technician(auth.uid())
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );

ALTER POLICY payables_delete ON public.payables
  USING (
    auth.uid() IS NOT NULL
    AND NOT public.is_technician(auth.uid())
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );

-- ── O que este arquivo NÃO faz, e por quê ───────────────────────────────────────
-- Os campos de valor de `service_orders` (grand_total, labor_cost_total, …) continuam
-- visíveis ao técnico. A decisão pedia para avaliar column-level grants; a avaliação está
-- registrada em audit/novos-achados.md (NOVO-006). Resumo: `REVOKE SELECT (coluna)` faria
-- o PostgREST responder 42501 em vez de omitir a coluna, e o frontend pede `select=*` —
-- quebraria a tela de OS para o técnico, que é a tela do trabalho dele.
