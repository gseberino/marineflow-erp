-- Pró-labore e salários deixam de ser visíveis para todo o financeiro.
--
-- Decisão do dono: quanto cada sócio retira e quanto cada pessoa ganha não é informação
-- que um assistente financeiro precise para conciliar extrato ou pagar fornecedor.
--
-- POR QUE NO BANCO E NÃO NA TELA: esconder no frontend é teatro. Quem tem login tem a
-- chave da API, e a chave lê a tabela inteira.

ALTER TABLE public.financial_categories
  ADD COLUMN IF NOT EXISTS sensitive boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.financial_categories.sensitive IS
  'Categoria cujos lançamentos só o administrador enxerga (pró-labore, folha).';

UPDATE public.financial_categories
SET sensitive = true
WHERE type = 'payable' AND name IN ('Pró-labore e retirada', 'Salários e encargos');

-- STABLE e SECURITY DEFINER porque roda dentro da política de RLS de payables: precisa
-- enxergar financial_categories independentemente de quem pergunta.
CREATE OR REPLACE FUNCTION public.categoria_e_sensivel(nome text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.financial_categories
    WHERE name = nome AND type = 'payable' AND sensitive
  );
$$;

REVOKE EXECUTE ON FUNCTION public.categoria_e_sensivel(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.categoria_e_sensivel(text) TO authenticated, service_role;

DROP POLICY IF EXISTS authenticated_all_payables ON public.payables;

CREATE POLICY payables_select ON public.payables
  FOR SELECT TO authenticated
  USING (
    auth.uid() IS NOT NULL
    AND (
      public.is_admin(auth.uid())
      OR expense_category IS NULL
      OR NOT public.categoria_e_sensivel(expense_category)
    )
  );

-- ATENÇÃO: escrita declarada POR COMANDO, nunca FOR ALL.
--
-- Políticas permissivas se combinam com OU, e FOR ALL inclui SELECT — uma política de
-- escrita com FOR ALL liberaria a leitura de tudo e anularia a restrição acima. Foi
-- exatamente o que aconteceu na primeira versão, e só um teste assumindo o papel de
-- usuário comum revelou: olhar a tela e ver o dado aparecer passa igual nos dois casos.
CREATE POLICY payables_insert ON public.payables
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payables_update ON public.payables
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY payables_delete ON public.payables
  FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);
