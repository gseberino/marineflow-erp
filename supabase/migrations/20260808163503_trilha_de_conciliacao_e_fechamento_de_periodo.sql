-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-08T16:34:58.934Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260808163503 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- FASE E — trilha imutável e fechamento de período.
--
-- Hoje o rastro está espalhado: `dismissed_by/at/kind` na transação, `decided_by/at` na
-- fila, a tabela `payments`. Serve para responder "o que aconteceu com ESTA linha", e não
-- responde "o que foi feito no mês passado, por quem, e com base em quê" — que é a
-- pergunta de quem audita ou fecha o exercício.

CREATE TABLE IF NOT EXISTS public.reconciliation_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ocorrido_em timestamptz NOT NULL DEFAULT now(),
  autor uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  /* conciliou | ignorou | devolveu | aprovou_proposta | reclassificou | fechou_periodo */
  acao text NOT NULL,
  bank_transaction_id uuid REFERENCES public.bank_transactions(id) ON DELETE SET NULL,
  payable_id uuid REFERENCES public.payables(id) ON DELETE SET NULL,
  receivable_id uuid REFERENCES public.receivables(id) ON DELETE SET NULL,
  finance_rule_id uuid REFERENCES public.finance_rules(id) ON DELETE SET NULL,
  valor numeric(14,2),
  detalhe text,
  /* O que mudou, para reconstruir a decisão sem depender da memória de ninguém. */
  antes jsonb,
  depois jsonb
);

ALTER TABLE public.reconciliation_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reconciliation_log FROM anon;

CREATE POLICY "financeiro le a trilha"
  ON public.reconciliation_log FOR SELECT TO authenticated
  USING (public.is_admin_or_financial(auth.uid()));

-- Sem policy de UPDATE nem DELETE, de propósito: trilha que se edita não é trilha. Só o
-- service_role (o motor) escreve, e ninguém apaga pela API.

CREATE INDEX IF NOT EXISTS idx_reconciliation_log_data
  ON public.reconciliation_log (ocorrido_em DESC);
CREATE INDEX IF NOT EXISTS idx_reconciliation_log_transacao
  ON public.reconciliation_log (bank_transaction_id) WHERE bank_transaction_id IS NOT NULL;

/**
 * Períodos fechados.
 *
 * Fechar o mês é dizer "estes números não mudam mais". Sem isso, uma conciliação feita
 * hoje pode alterar o resultado de um mês já reportado ao contador — e ninguém percebe,
 * porque o relatório é recalculado a cada abertura.
 */
CREATE TABLE IF NOT EXISTS public.periodos_fechados (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ano integer NOT NULL,
  mes integer NOT NULL CHECK (mes BETWEEN 1 AND 12),
  fechado_em timestamptz NOT NULL DEFAULT now(),
  fechado_por uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  reaberto_em timestamptz,
  reaberto_por uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  /* Reabrir exige dizer por quê: é a diferença entre corrigir um erro e maquiar. */
  motivo_da_reabertura text,
  UNIQUE (ano, mes)
);

ALTER TABLE public.periodos_fechados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.periodos_fechados FROM anon;

CREATE POLICY "financeiro le periodos" ON public.periodos_fechados
  FOR SELECT TO authenticated USING (public.is_admin_or_financial(auth.uid()));
CREATE POLICY "admin fecha periodo" ON public.periodos_fechados
  FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "admin reabre periodo" ON public.periodos_fechados
  FOR UPDATE TO authenticated USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

/**
 * A trava de verdade: período fechado não aceita lançamento novo.
 *
 * Uma regra escrita só na tela é sugestão — quem chama a API pula. Aqui ela vive onde o
 * dado vive, e vale para o painel, para o agente e para qualquer integração futura.
 */
CREATE OR REPLACE FUNCTION public.periodo_esta_fechado(p_data date)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.periodos_fechados
     WHERE ano = EXTRACT(YEAR FROM p_data)::int
       AND mes = EXTRACT(MONTH FROM p_data)::int
       AND reaberto_em IS NULL
  );
$$;

REVOKE EXECUTE ON FUNCTION public.periodo_esta_fechado(date) FROM anon;

CREATE OR REPLACE FUNCTION public.bloqueia_lancamento_em_periodo_fechado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.periodo_esta_fechado(NEW.issue_date) THEN
    RAISE EXCEPTION 'O período de % está fechado. Reabra-o para lançar nesta data.',
      to_char(NEW.issue_date, 'MM/YYYY');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payables_periodo_fechado ON public.payables;
CREATE TRIGGER trg_payables_periodo_fechado
  BEFORE INSERT ON public.payables
  FOR EACH ROW EXECUTE FUNCTION public.bloqueia_lancamento_em_periodo_fechado();

DROP TRIGGER IF EXISTS trg_receivables_periodo_fechado ON public.receivables;
CREATE TRIGGER trg_receivables_periodo_fechado
  BEFORE INSERT ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.bloqueia_lancamento_em_periodo_fechado();
