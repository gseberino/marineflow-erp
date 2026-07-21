-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: numeração da NF-e de produção configurável (corrige Rejeição 539)
--   Causa: empresa que já emitiu NF-e em produção por outro sistema (ex.: HBR,
--   série 1 nº 1 em 2023). Nossa numeração recomeçava do 1 → a SEFAZ recusa
--   (539 "número já utilizado, com diferença na chave").
--   • company_fiscal_settings.nfe_series_producao: série de produção escolhida
--     (uma série NOVA começa a numeração limpa; homologação fica sempre na 2).
--   • RPC set_fiscal_next_number: admin alinha o próximo número com o histórico
--     da SEFAZ (com guarda contra apontar para um número já autorizado por nós).
-- Aditiva e reversível. Sem segredos.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.company_fiscal_settings
  ADD COLUMN IF NOT EXISTS nfe_series_producao int NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.company_fiscal_settings.nfe_series_producao IS
  'Série da NF-e em produção. Empresas que já emitiram em outro sistema usam uma série nova para começar a numeração limpa e evitar Rejeição 539.';

CREATE OR REPLACE FUNCTION public.set_fiscal_next_number(
  p_document_type text,
  p_series        int,
  p_environment   text,
  p_next_number   int
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_authorized int;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_next_number < 1 THEN
    RAISE EXCEPTION 'O próximo número deve ser maior ou igual a 1.';
  END IF;
  IF p_environment NOT IN ('homologacao','producao') THEN
    RAISE EXCEPTION 'Ambiente inválido.';
  END IF;

  -- Guarda: não apontar para um número <= a uma NF-e JÁ AUTORIZADA por nós nessa
  -- série/ambiente — isso geraria duplicidade local (a SEFAZ também rejeitaria).
  SELECT MAX(number) INTO v_max_authorized
    FROM issued_fiscal_documents
   WHERE document_type = p_document_type
     AND series = p_series
     AND environment = p_environment
     AND status = 'authorized';
  IF v_max_authorized IS NOT NULL AND p_next_number <= v_max_authorized THEN
    RAISE EXCEPTION 'Já existe NF-e autorizada com número % nessa série/ambiente. O próximo número deve ser maior que %.',
      v_max_authorized, v_max_authorized;
  END IF;

  INSERT INTO fiscal_document_sequences (document_type, series, environment, last_number, updated_at)
  VALUES (p_document_type, p_series, p_environment, p_next_number - 1, now())
  ON CONFLICT (document_type, series, environment)
  DO UPDATE SET last_number = p_next_number - 1, updated_at = now();

  RETURN p_next_number;
END;
$$;

REVOKE ALL     ON FUNCTION public.set_fiscal_next_number(text,int,text,int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_fiscal_next_number(text,int,text,int) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_fiscal_next_number(text,int,text,int) TO authenticated;
