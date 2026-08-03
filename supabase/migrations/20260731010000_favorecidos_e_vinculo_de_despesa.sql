-- Quem recebe dinheiro da empresa e não é fornecedor nem usuário do sistema.
--
-- POR QUE UMA TABELA PRÓPRIA (decisão do usuário): sócio, diarista e prestador não cabem
-- nos cadastros existentes. Em `suppliers` misturariam quem vende peça com quem presta
-- hora e com sócio — os 530 fornecedores deixariam de ser uma lista de fornecedores. Em
-- `app_users` obrigariam a criar login para quem nunca vai entrar no sistema, e um
-- diarista de um dia viraria usuário permanente.
--
-- O que motiva: R$ 36.415 em pró-labore e R$ 6.657 entre salários e serviços de terceiros
-- que hoje não têm a quem pertencer. E `app_users` tem `pix_key` desde sempre, com ZERO
-- linhas preenchidas — sinal de que o lugar estava errado, não de que o dado não importa.

CREATE TABLE IF NOT EXISTS public.payees (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  name          text NOT NULL,
  /** O que a pessoa é para a empresa — muda a categoria contábil do pagamento. */
  kind          text NOT NULL DEFAULT 'prestador' CHECK (kind IN (
                  'socio',        -- pró-labore e retirada: NÃO é despesa operacional
                  'funcionario',  -- folha e encargos
                  'diarista',     -- apoio pontual, sem vínculo
                  'prestador'     -- pessoa jurídica de serviço
                )),
  document      text,             -- CPF ou CNPJ, só dígitos
  phone         text,
  email         text,

  /** Para onde o dinheiro vai. É o que evita abrir o internet banking para conferir. */
  pix_key       text,
  pix_key_type  text CHECK (pix_key_type IN ('cpf','cnpj','email','telefone','aleatoria')),
  bank_name     text,
  bank_branch   text,
  bank_account  text,
  account_type  text CHECK (account_type IN ('corrente','poupanca','pagamento')),

  /** Categoria de despesa padrão deste favorecido — o pagamento já nasce classificado. */
  default_category text,

  notes         text,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Documento identifica pessoa: dois cadastros do mesmo CPF viram dois históricos da mesma
-- pessoa, e nenhum dos dois conta a verdade. Parcial porque documento é opcional
-- (diarista pode entrar só com nome antes de a empresa ter o CPF).
CREATE UNIQUE INDEX IF NOT EXISTS payees_documento_unico
  ON public.payees (document) WHERE document IS NOT NULL AND document <> '';

CREATE INDEX IF NOT EXISTS idx_payees_ativos ON public.payees (active, kind, name);

COMMENT ON TABLE public.payees IS
  'Favorecidos que recebem dinheiro sem ser fornecedor nem usuário: sócios, funcionários, diaristas e prestadores.';
COMMENT ON COLUMN public.payees.kind IS
  'socio = pró-labore (fora do resultado operacional); funcionario = folha; diarista = apoio pontual; prestador = PJ de serviço.';

ALTER TABLE public.payees ENABLE ROW LEVEL SECURITY;

-- Dado sensível (CPF, conta, Pix): só quem cuida do dinheiro vê.
DROP POLICY IF EXISTS payees_select ON public.payees;
CREATE POLICY payees_select ON public.payees
  FOR SELECT TO authenticated USING (public.is_admin_or_financial(auth.uid()));

DROP POLICY IF EXISTS payees_write ON public.payees;
CREATE POLICY payees_write ON public.payees
  FOR ALL TO authenticated
  USING (public.is_admin_or_financial(auth.uid()))
  WITH CHECK (public.is_admin_or_financial(auth.uid()));

REVOKE ALL ON public.payees FROM anon;

DROP TRIGGER IF EXISTS payees_updated_at ON public.payees;
CREATE TRIGGER payees_updated_at
  BEFORE UPDATE ON public.payees
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- A quem a despesa pertence, quando não é a um fornecedor.
ALTER TABLE public.payables
  ADD COLUMN IF NOT EXISTS payee_id uuid REFERENCES public.payees(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_payables_payee ON public.payables (payee_id) WHERE payee_id IS NOT NULL;

COMMENT ON COLUMN public.payables.payee_id IS
  'Favorecido pessoa física/prestador. Complementar a supplier_id, nunca simultâneo a ele.';

-- A proposta carrega a sugestão até a aprovação, como já faz com fornecedor e categoria.
ALTER TABLE public.finance_review_queue
  ADD COLUMN IF NOT EXISTS suggested_payee_id uuid REFERENCES public.payees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS suggested_service_order_id uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS suggested_purchase_order_id uuid REFERENCES public.purchase_orders(id) ON DELETE SET NULL;
