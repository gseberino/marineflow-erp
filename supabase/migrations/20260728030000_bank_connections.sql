-- Conexões bancárias de leitura (Open Finance via Pluggy / Meu Pluggy).
--
-- Um "item" no Pluggy é uma conexão viva com um banco: o consentimento fica no Meu Pluggy
-- e a API expõe as contas e transações daquele vínculo. Guardamos o id do item porque é
-- por ele que a sincronização puxa os dados — e porque no modelo gratuito (conector
-- MeuPluggy) não existe widget de conexão dentro do ERP: a conta é ligada no portal e o
-- sistema apenas consome.
--
-- Registrar o resultado de cada sincronização é parte do desenho, não enfeite: extrato que
-- para de atualizar em silêncio é pior do que extrato ausente, porque ninguém percebe. O
-- consentimento do Open Finance também expira (~12 meses), e a data da última sincronização
-- bem-sucedida é o sinal de que ele caiu.

CREATE TABLE IF NOT EXISTS public.bank_connections (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider      text NOT NULL DEFAULT 'pluggy',
  /** Id do item no provedor — a chave de tudo. */
  external_id   text NOT NULL,
  /** Como aparece para o usuário: "C6 — conta PJ". */
  label         text NOT NULL,
  institution   text,
  /** bank | credit_card: define como as transações entram no extrato. */
  account_kind  text NOT NULL DEFAULT 'bank' CHECK (account_kind IN ('bank', 'credit_card')),
  active        boolean NOT NULL DEFAULT true,

  last_synced_at      timestamptz,
  last_sync_status    text CHECK (last_sync_status IN ('ok', 'error', 'never')),
  last_sync_message   text,
  last_sync_imported  integer,
  /** Data da transação mais recente já trazida: evita varrer o histórico inteiro. */
  last_transaction_date date,

  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS bank_connections_provider_external
  ON public.bank_connections (provider, external_id);

COMMENT ON TABLE public.bank_connections IS
  'Conexões de leitura de extrato (Open Finance). external_id = itemId do Pluggy.';
COMMENT ON COLUMN public.bank_connections.last_synced_at IS
  'Última sincronização bem-sucedida. Serve de alarme: consentimento do Open Finance expira e a coleta para em silêncio.';

ALTER TABLE public.bank_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bank_connections_select ON public.bank_connections;
CREATE POLICY bank_connections_select ON public.bank_connections
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

-- Conectar/desconectar banco é ato financeiro: mesma régua de quem registra pagamento.
DROP POLICY IF EXISTS bank_connections_write ON public.bank_connections;
CREATE POLICY bank_connections_write ON public.bank_connections
  FOR ALL TO authenticated
  USING (public.is_admin_or_financial(auth.uid()))
  WITH CHECK (public.is_admin_or_financial(auth.uid()));

DROP TRIGGER IF EXISTS bank_connections_updated_at ON public.bank_connections;
CREATE TRIGGER bank_connections_updated_at
  BEFORE UPDATE ON public.bank_connections
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Liga a transação importada à conexão de origem. Sem isso, extrato de duas contas vira
-- uma pilha só e não há como saber de onde veio cada linha.
ALTER TABLE public.bank_transactions
  ADD COLUMN IF NOT EXISTS bank_connection_id uuid REFERENCES public.bank_connections(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bank_transactions_connection
  ON public.bank_transactions (bank_connection_id);
