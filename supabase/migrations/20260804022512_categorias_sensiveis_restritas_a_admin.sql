-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-04T02:25:09.327Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260804022512 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Pró-labore e salários deixam de ser visíveis para todo o financeiro.
--
-- Decisão do dono: quanto cada sócio retira e quanto cada pessoa ganha não é informação
-- que um assistente financeiro precise para conciliar extrato ou pagar fornecedor.
--
-- POR QUE NO BANCO E NÃO NA TELA: esconder no frontend é teatro. Quem tem login tem a
-- chave da API, e a chave lê a tabela inteira. Proteção que só existe no React protege
-- contra o olhar casual, não contra quem quer ver — e aqui o dado é salário de gente.

ALTER TABLE public.financial_categories
  ADD COLUMN IF NOT EXISTS sensitive boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.financial_categories.sensitive IS
  'Categoria cujos lançamentos só o administrador enxerga (pró-labore, folha).';

UPDATE public.financial_categories
SET sensitive = true
WHERE type = 'payable' AND name IN ('Pró-labore e retirada', 'Salários e encargos');

/**
 * A categoria do lançamento é restrita?
 *
 * STABLE e SECURITY DEFINER porque roda dentro da política de RLS de payables: precisa
 * enxergar financial_categories independentemente de quem pergunta, senão a política
 * dependeria da permissão do próprio usuário sobre a tabela de categorias.
 */
CREATE OR REPLACE FUNCTION public.categoria_e_sensivel(nome text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.financial_categories
    WHERE name = nome AND type = 'payable' AND sensitive
  );
$$;

REVOKE EXECUTE ON FUNCTION public.categoria_e_sensivel(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.categoria_e_sensivel(text) TO authenticated, service_role;

-- Substitui a política de leitura: continua valendo para todo authenticated, mas linha de
-- categoria sensível só aparece para admin. As demais operações seguem como estavam.
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

CREATE POLICY payables_write ON public.payables
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
