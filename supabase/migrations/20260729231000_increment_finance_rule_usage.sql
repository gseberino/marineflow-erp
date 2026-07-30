-- Contador de uso da regra. Existe como função porque `times_applied = times_applied + 1`
-- feito por leitura-e-escrita perde incrementos quando duas aprovações rodam juntas.
CREATE OR REPLACE FUNCTION public.increment_finance_rule_usage(rule_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.finance_rules
  SET times_applied = times_applied + 1, last_applied_at = now()
  WHERE id = rule_id;
$$;

REVOKE EXECUTE ON FUNCTION public.increment_finance_rule_usage(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_finance_rule_usage(uuid) TO authenticated, service_role;
