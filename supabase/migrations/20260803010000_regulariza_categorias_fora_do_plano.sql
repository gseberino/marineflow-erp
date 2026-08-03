-- R$ 64.252 estavam em categorias que NÃO existem no plano de contas.
--
-- Categoria sem correspondência não tem `dre_group`, e sem grupo o valor não entra em
-- nenhuma linha do resultado: some, sem erro e sem aviso. Como a categoria é texto livre
-- nos lançamentos, nada impedia a divergência.
--
-- As duas achadas e de onde vieram:
--   · "Compras de Mercadorias" (R$ 59.671) — nasceu na importação de nota fiscal, e depois
--     se PROPAGOU: o aprendizado por fornecedor a adotou como padrão da Kamell e a aplicou
--     a lançamentos novos vindos do extrato. Um engano virou política.
--   · "Outros" (R$ 4.581) — resquício da lista fixa de dez itens que a Conciliação usava
--     no lugar do plano de contas. Lançado em 03/08, o que confirma que o problema estava
--     vivo até a correção de hoje.

INSERT INTO public.financial_categories (name, type, dre_group, sort_order, color, active, description)
VALUES ('Compras de mercadorias', 'payable', 'custo_direto', 65, '#0ea5e9', true,
        'Mercadoria adquirida para revenda, geralmente entrando por nota fiscal')
ON CONFLICT (name, type) DO UPDATE
  SET active = true, dre_group = EXCLUDED.dre_group;

UPDATE public.payables
SET expense_category = 'Compras de mercadorias'
WHERE expense_category = 'Compras de Mercadorias';

UPDATE public.payables
SET expense_category = 'Outras despesas'
WHERE expense_category = 'Outros';

-- Rede de segurança: categoria fora do plano de contas vira erro de escrita, não
-- descoberta tardia num relatório.
CREATE OR REPLACE FUNCTION public.valida_categoria_de_despesa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.expense_category IS NULL OR NEW.expense_category = '' THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.financial_categories
    WHERE name = NEW.expense_category AND type = 'payable' AND active
  ) THEN
    RAISE EXCEPTION
      'Categoria "%" não existe no plano de contas. Crie-a antes de usar, senão o valor some do resultado.',
      NEW.expense_category
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payables_categoria_valida ON public.payables;
CREATE TRIGGER payables_categoria_valida
  BEFORE INSERT OR UPDATE OF expense_category ON public.payables
  FOR EACH ROW EXECUTE FUNCTION public.valida_categoria_de_despesa();
