-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-04T00:24:27.590Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260804002431 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Impede que voltem os dois casos achados na auditoria de 03/08/2026.
--
-- Não bastava corrigir as duas linhas: a causa era a ausência de regra. Uma OS concluída
-- com valor zero (cortesia, garantia) gerava recebível de R$ 0,00 que ficava para sempre
-- na fila de cobrança — e cobrar R$ 0,00 não é uma tarefa, é ruído. E um saldo emitido
-- hoje podia nascer vencendo ontem, virando "atrasado" antes de existir.
--
-- Por que trigger e não CHECK: o CHECK não sabe distinguir "vence na entrega" (onde a data
-- é só referência e a regra é outra) de uma data realmente incoerente.

CREATE OR REPLACE FUNCTION public.valida_recebivel_coerente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Recebível sem valor não é cobrança. Serviço de cortesia é decisão legítima; o que não
  -- pode é virar uma linha que ninguém consegue baixar nem cobrar.
  IF NEW.amount IS NOT NULL AND NEW.amount <= 0 AND coalesce(NEW.status, '') <> 'cancelled' THEN
    RAISE EXCEPTION
      'Recebível precisa de valor maior que zero. Serviço sem cobrança não gera conta a receber.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Vencimento anterior à emissão só faz sentido quando quem manda é a entrega: aí a data
  -- é referência, não prazo. Fora disso, é engano — e nasce vencido.
  IF NEW.due_date IS NOT NULL AND NEW.issue_date IS NOT NULL
     AND NEW.due_date < NEW.issue_date
     AND NOT coalesce(NEW.due_on_completion, false) THEN
    RAISE EXCEPTION
      'Vencimento (%) é anterior à emissão (%). Se o saldo vence na entrega, marque "vence na conclusão" em vez de datar para trás.',
      NEW.due_date, NEW.issue_date
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS receivables_coerencia ON public.receivables;
CREATE TRIGGER receivables_coerencia
  BEFORE INSERT OR UPDATE OF amount, due_date, issue_date, due_on_completion, status
  ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.valida_recebivel_coerente();
