-- Regras do financeiro: o que o gestor ENSINA ao sistema sobre o próprio dinheiro.
--
-- POR QUE EXISTE: o motor de propostas hoje deduz a categoria de duas formas — regra de
-- texto genérica ("POSTO" indica combustível) e histórico dos lançamentos daquele
-- fornecedor. As duas são calados: o gestor não consegue dizer "PIX para Fulano é sempre
-- pró-labore", nem corrigir uma dedução errada de forma permanente. Corrigir 40 vezes a
-- mesma linha é o oposto de uma ferramenta que aprende.
--
-- O DESENHO segue a decisão do usuário: "o importante é ter várias opções para ensinar e
-- corrigir a IA, mas ela também pode recomendar de acordo com o que identifica".
--   · a AUTONOMIA é por regra, não global — cada uma carrega quanto se confia nela;
--   · a IA propõe regras (status 'proposed') a partir do que viu repetir, e quem aceita
--     é o gestor. Regra que o sistema cria sozinha e passa a aplicar é regra que ninguém
--     revisou.
--
-- PRECEDÊNCIA na classificação (a mais específica ganha):
--   1. regra por documento  — CNPJ é identidade, não se confunde
--   2. regra por fornecedor — quem recebeu o dinheiro
--   3. regra por texto      — trecho do histórico
--   4. histórico aprendido  — o que já foi lançado para aquele fornecedor
--   5. regra genérica de mercado (REGRAS_CATEGORIA, no código)

CREATE TABLE IF NOT EXISTS public.finance_rules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  /** COMO a regra reconhece a transação. */
  match_type    text NOT NULL CHECK (match_type IN (
                  'document',        -- CNPJ/CPF da contraparte (identidade)
                  'supplier',        -- fornecedor já cadastrado
                  'counterparty',    -- nome de quem recebeu/pagou
                  'text'             -- trecho do histórico do extrato
                )),
  /** O valor comparado: documento, uuid do fornecedor, nome ou trecho de texto. */
  match_value   text NOT NULL,
  /** Entrada, saída ou tanto faz. Quase toda regra é de saída. */
  direction     text NOT NULL DEFAULT 'debit' CHECK (direction IN ('debit', 'credit', 'any')),
  /** Faixa de valor opcional: "acima de X é investimento, abaixo é manutenção". */
  min_amount    numeric(14,2),
  max_amount    numeric(14,2),

  /** O QUE a regra faz quando reconhece. */
  set_category    text,
  set_dre_group   text,
  set_supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,

  /** QUANTO se confia nela. Decisão por regra, não do sistema inteiro. */
  autonomy      text NOT NULL DEFAULT 'suggest' CHECK (autonomy IN (
                  'suggest',   -- preenche a proposta, mas o gestor confirma
                  'apply'      -- lança sozinha; a linha nasce marcada como criada por regra
                )),

  /** De onde veio e em que pé está. */
  origin        text NOT NULL DEFAULT 'user' CHECK (origin IN ('user', 'ai')),
  status        text NOT NULL DEFAULT 'active' CHECK (status IN (
                  'active',    -- valendo
                  'paused',    -- desligada sem perder o histórico
                  'proposed',  -- a IA sugeriu; aguarda o gestor aceitar
                  'rejected'   -- o gestor recusou; não propor de novo
                )),

  /** Por que a IA propôs isto — sem o motivo, aceitar é apostar. */
  reasoning     text,
  note          text,

  /** Quanto a regra trabalhou. É o que separa regra útil de regra esquecida. */
  times_applied   integer NOT NULL DEFAULT 0,
  last_applied_at timestamptz,

  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Uma regra viva por alvo: ensinar duas coisas diferentes sobre o mesmo fornecedor produz
-- resultado imprevisível (vence quem o banco devolver primeiro). Parcial porque regra
-- pausada ou recusada é histórico e pode conviver com a nova.
CREATE UNIQUE INDEX IF NOT EXISTS finance_rules_uma_por_alvo
  ON public.finance_rules (match_type, lower(match_value), direction)
  WHERE status IN ('active', 'proposed');

CREATE INDEX IF NOT EXISTS idx_finance_rules_ativas
  ON public.finance_rules (status, match_type);

COMMENT ON TABLE public.finance_rules IS
  'O que o gestor ensinou ao sistema sobre as próprias despesas. A IA propõe (status proposed); quem aceita é gente.';
COMMENT ON COLUMN public.finance_rules.autonomy IS
  'suggest = preenche e espera confirmação; apply = lança sozinha, marcada como criada por regra.';

ALTER TABLE public.finance_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS finance_rules_select ON public.finance_rules;
CREATE POLICY finance_rules_select ON public.finance_rules
  FOR SELECT TO authenticated USING (public.is_admin_or_financial(auth.uid()));

DROP POLICY IF EXISTS finance_rules_write ON public.finance_rules;
CREATE POLICY finance_rules_write ON public.finance_rules
  FOR ALL TO authenticated
  USING (public.is_admin_or_financial(auth.uid()))
  WITH CHECK (public.is_admin_or_financial(auth.uid()));

DROP TRIGGER IF EXISTS finance_rules_updated_at ON public.finance_rules;
CREATE TRIGGER finance_rules_updated_at
  BEFORE UPDATE ON public.finance_rules
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Guarda qual regra originou a proposta: sem isso não dá para saber se o número veio de
-- uma decisão do gestor ou de um palpite do sistema — nem medir se a regra acerta.
ALTER TABLE public.finance_review_queue
  ADD COLUMN IF NOT EXISTS applied_rule_id uuid REFERENCES public.finance_rules(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.finance_review_queue.applied_rule_id IS
  'Regra que classificou esta proposta. Permite auditar a regra pelo resultado dela.';
