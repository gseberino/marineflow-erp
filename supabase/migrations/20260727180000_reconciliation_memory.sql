-- Memória de conciliação: o sistema aprende como cada cliente aparece no extrato.
--
-- Motivo: o banco escreve o pagador de um jeito ("PIX RECEB MARINA SOL LTDA"), o cadastro
-- guarda de outro ("Marina do Sol"), e o operador resolve essa ligação mentalmente toda vez.
-- Cada conciliação manual é, na prática, um exemplo rotulado: "este texto de extrato é
-- deste cliente". Guardar isso é o que faz a taxa de acerto subir com o uso, em vez de
-- ficar parada na heurística inicial.
--
-- `statement_key` é a assinatura do histórico: tokens identificadores em ordem alfabética,
-- sem ruído bancário (PIX, TED, RECEBIDO...) e sem acento. Assim "PIX RECEBIDO MARINA SOL"
-- e "TED MARINA SOL LTDA" viram a mesma chave.

CREATE TABLE IF NOT EXISTS public.reconciliation_memory (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  statement_key text NOT NULL,
  client_id     uuid REFERENCES public.clients(id) ON DELETE CASCADE,
  candidate_kind text,
  hits          integer NOT NULL DEFAULT 1,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Uma linha por (assinatura, cliente): reconciliar de novo incrementa em vez de duplicar.
CREATE UNIQUE INDEX IF NOT EXISTS reconciliation_memory_key_client
  ON public.reconciliation_memory (statement_key, client_id);

CREATE INDEX IF NOT EXISTS idx_reconciliation_memory_key
  ON public.reconciliation_memory (statement_key);

COMMENT ON TABLE public.reconciliation_memory IS
  'Aprendizado da conciliação: liga a assinatura do histórico bancário ao cliente confirmado pelo operador.';
COMMENT ON COLUMN public.reconciliation_memory.statement_key IS
  'Tokens identificadores do histórico, normalizados e ordenados. Ver normalizeText/statementSignature em _shared/banking/matching.ts.';
COMMENT ON COLUMN public.reconciliation_memory.hits IS
  'Quantas vezes essa ligação foi confirmada. Mais confirmações, mais confiança no casamento.';

ALTER TABLE public.reconciliation_memory ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reconciliation_memory_select ON public.reconciliation_memory;
CREATE POLICY reconciliation_memory_select ON public.reconciliation_memory
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS reconciliation_memory_write ON public.reconciliation_memory;
CREATE POLICY reconciliation_memory_write ON public.reconciliation_memory
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- Registra (ou reforça) uma ligação aprendida. SECURITY DEFINER para que a edge function
-- e o agente gravem sem depender do RLS do chamador, mantendo a checagem de sessão acima.
CREATE OR REPLACE FUNCTION public.remember_reconciliation(
  p_statement_key text,
  p_client_id     uuid,
  p_candidate_kind text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_statement_key IS NULL OR length(trim(p_statement_key)) < 3 OR p_client_id IS NULL THEN
    RETURN; -- assinatura fraca demais para virar aprendizado
  END IF;

  INSERT INTO public.reconciliation_memory (statement_key, client_id, candidate_kind)
  VALUES (trim(p_statement_key), p_client_id, p_candidate_kind)
  ON CONFLICT (statement_key, client_id) DO UPDATE
    SET hits = public.reconciliation_memory.hits + 1,
        last_seen_at = now(),
        candidate_kind = COALESCE(EXCLUDED.candidate_kind, public.reconciliation_memory.candidate_kind);
END;
$$;

GRANT EXECUTE ON FUNCTION public.remember_reconciliation TO authenticated, service_role;
