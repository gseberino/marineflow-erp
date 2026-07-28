-- Cobranças emitidas (boleto / Pix) — base da emissão pelo banco.
--
-- Fica separada de `receivables` porque são coisas diferentes: a conta a receber é o
-- direito de crédito (nasce da venda), a cobrança é o instrumento de recebimento emitido
-- no banco. Uma conta pode ter mais de uma cobrança ao longo do tempo — boleto vencido e
-- reemitido, boleto cancelado e trocado por Pix — e cada uma tem o próprio ciclo de vida.
--
-- `provider` + `provider_charge_id` é a chave externa do banco: é por ela que o webhook de
-- liquidação encontra a cobrança, e o índice único impede que a mesma cobrança seja
-- registrada duas vezes se o provedor reenviar o evento.

CREATE TABLE IF NOT EXISTS public.bank_charges (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receivable_id     uuid REFERENCES public.receivables(id) ON DELETE SET NULL,
  service_order_id  uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  client_id         uuid REFERENCES public.clients(id) ON DELETE SET NULL,

  provider          text NOT NULL,
  provider_charge_id text,
  kind              text NOT NULL CHECK (kind IN ('boleto', 'pix', 'bolepix')),

  amount            numeric(14,2) NOT NULL CHECK (amount > 0),
  due_date          date,
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','registered','paid','overdue','cancelled','failed')),

  -- Dados que o cliente usa para pagar.
  digitable_line    text,
  barcode           text,
  pix_copy_paste    text,
  pix_qr_base64     text,
  pix_end_to_end_id text,
  pdf_url           text,

  paid_at           timestamptz,
  paid_amount       numeric(14,2),
  /** Resposta bruta do provedor: indispensável para investigar divergência sem adivinhar. */
  raw               jsonb,
  error_message     text,

  created_by        uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS bank_charges_provider_ref
  ON public.bank_charges (provider, provider_charge_id)
  WHERE provider_charge_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bank_charges_receivable ON public.bank_charges (receivable_id);
CREATE INDEX IF NOT EXISTS idx_bank_charges_abertas
  ON public.bank_charges (status, due_date)
  WHERE status IN ('pending','registered','overdue');
-- A conciliação casa o Pix da cobrança com a linha do extrato por este identificador.
CREATE INDEX IF NOT EXISTS idx_bank_charges_pix_e2e
  ON public.bank_charges (pix_end_to_end_id)
  WHERE pix_end_to_end_id IS NOT NULL;

COMMENT ON TABLE public.bank_charges IS
  'Cobranças emitidas no banco (boleto/Pix). Instrumento de recebimento, distinto da conta a receber.';
COMMENT ON COLUMN public.bank_charges.raw IS
  'Resposta bruta do provedor, para investigar divergência sem depender de log.';

ALTER TABLE public.bank_charges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bank_charges_select ON public.bank_charges;
CREATE POLICY bank_charges_select ON public.bank_charges
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

-- Emitir cobrança é ato financeiro: mesma régua de quem pode registrar pagamento.
DROP POLICY IF EXISTS bank_charges_write ON public.bank_charges;
CREATE POLICY bank_charges_write ON public.bank_charges
  FOR ALL TO authenticated
  USING (public.is_admin_or_financial(auth.uid()))
  WITH CHECK (public.is_admin_or_financial(auth.uid()));

DROP TRIGGER IF EXISTS bank_charges_updated_at ON public.bank_charges;
CREATE TRIGGER bank_charges_updated_at
  BEFORE UPDATE ON public.bank_charges
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
