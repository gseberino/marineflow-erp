-- Caixa de entrada financeira: o que o sistema propõe e o gestor decide.
--
-- Existe porque o portão de aprovação atual (ai_operator_pending_actions) foi desenhado
-- para ações avulsas do agente no chat — uma por vez, com confirmação individual. O que a
-- operação exige agora é outra coisa: centenas de propostas geradas em bloco a partir do
-- extrato, que precisam ser lidas em lote, com o motivo à vista e a possibilidade de
-- corrigir antes de aceitar. Misturar os dois fluxos deixaria os dois piores.
--
-- Nada aqui movimenta dinheiro. Uma linha aprovada vira registro de despesa ou receita
-- (contabilidade); pagar continua sendo ato humano em outro lugar.

CREATE TABLE IF NOT EXISTS public.finance_review_queue (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  /** O que o sistema quer fazer. */
  kind          text NOT NULL CHECK (kind IN (
                  'create_payable',      -- saída sem despesa correspondente
                  'create_receivable',   -- entrada sem receita correspondente
                  'internal_transfer',   -- as duas pernas de uma transferência própria
                  'categorize',          -- lançamento existente sem categoria
                  'anomaly'              -- algo fora do padrão: só reporta
                )),
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected','superseded')),

  /** De onde a proposta nasceu — é o que torna tudo reversível e auditável. */
  bank_transaction_id uuid REFERENCES public.bank_transactions(id) ON DELETE CASCADE,
  /** Segunda perna, quando a proposta liga duas transações. */
  related_transaction_id uuid REFERENCES public.bank_transactions(id) ON DELETE SET NULL,

  /** Resumo em linguagem de gente, para o gestor decidir sem abrir nada. */
  title         text NOT NULL,
  /** Por que o sistema propôs isto. A trilha registra a decisão, não só a ação. */
  reasoning     text,
  /** 0 a 100. Abaixo do corte, a proposta pede atenção em vez de seguir no lote. */
  confidence    integer NOT NULL DEFAULT 50 CHECK (confidence BETWEEN 0 AND 100),

  /** Campos já preenchidos do lançamento proposto; o gestor pode corrigir antes de aceitar. */
  suggested_amount   numeric(14,2),
  suggested_date     date,
  suggested_category text,
  suggested_supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
  suggested_client_id   uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  suggested_description text,
  /** Grupo do plano de contas: separa o que entra no resultado do que não entra. */
  dre_group     text,

  /** O que foi criado ao aprovar — o fio para desfazer. */
  created_payable_id    uuid REFERENCES public.payables(id) ON DELETE SET NULL,
  created_receivable_id uuid REFERENCES public.receivables(id) ON DELETE SET NULL,

  decided_by    uuid,
  decided_at    timestamptz,
  decision_note text,

  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Uma proposta viva por transação: reprocessar o extrato não pode empilhar duplicatas na
-- fila do gestor. Parcial porque decisões antigas ficam guardadas como histórico.
CREATE UNIQUE INDEX IF NOT EXISTS finance_review_uma_por_transacao
  ON public.finance_review_queue (bank_transaction_id, kind)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_finance_review_fila
  ON public.finance_review_queue (status, confidence DESC, created_at);

COMMENT ON TABLE public.finance_review_queue IS
  'Propostas do sistema aguardando decisão do gestor. Aprovar cria lançamento; nada aqui movimenta dinheiro.';
COMMENT ON COLUMN public.finance_review_queue.reasoning IS
  'Por que o sistema propôs isto — a trilha guarda a decisão, não apenas a ação.';

ALTER TABLE public.finance_review_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS finance_review_select ON public.finance_review_queue;
CREATE POLICY finance_review_select ON public.finance_review_queue
  FOR SELECT TO authenticated USING (public.is_admin_or_financial(auth.uid()));

DROP POLICY IF EXISTS finance_review_write ON public.finance_review_queue;
CREATE POLICY finance_review_write ON public.finance_review_queue
  FOR ALL TO authenticated
  USING (public.is_admin_or_financial(auth.uid()))
  WITH CHECK (public.is_admin_or_financial(auth.uid()));

DROP TRIGGER IF EXISTS finance_review_updated_at ON public.finance_review_queue;
CREATE TRIGGER finance_review_updated_at
  BEFORE UPDATE ON public.finance_review_queue
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Liga o lançamento à transação que o originou, nos dois sentidos: sem isto não há como
-- saber que uma despesa nasceu do extrato, nem impedir que ela seja criada duas vezes.
ALTER TABLE public.payables
  ADD COLUMN IF NOT EXISTS bank_transaction_id uuid REFERENCES public.bank_transactions(id) ON DELETE SET NULL;
ALTER TABLE public.receivables
  ADD COLUMN IF NOT EXISTS bank_transaction_id uuid REFERENCES public.bank_transactions(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS payables_uma_por_transacao
  ON public.payables (bank_transaction_id) WHERE bank_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS receivables_uma_por_transacao
  ON public.receivables (bank_transaction_id) WHERE bank_transaction_id IS NOT NULL;
