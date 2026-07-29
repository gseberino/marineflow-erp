-- Fixa o search_path das 10 funções SECURITY INVOKER que ainda o deixavam livre
-- (advisor "Function Search Path Mutable" / linter 0011).
--
-- Complementa 20260728010000_search_path_security_definer.sql, que já fixou as
-- funções SECURITY DEFINER (risco alto). Estas 10 são todas SECURITY INVOKER
-- (rodam com o privilégio de quem chama) — o risco é baixo, mas o linter sinaliza
-- como higiene: sem search_path próprio, a função resolve nomes não qualificados
-- pelo caminho de quem a chama.
--
-- Seguro de aplicar: ALTER FUNCTION ... SET search_path NÃO altera o corpo, só fixa
-- o ambiente de resolução de nomes. Fixado em 'public' (e não em '') justamente
-- para preservar a resolução dos nomes não qualificados que os corpos já usam —
-- assim o comportamento observável não muda. Mesmo padrão de
-- 20260728010000_search_path_security_definer.sql.
--
-- Assinaturas conferidas em pg_proc antes de alterar (prosecdef = false nas 10).

ALTER FUNCTION public.log_product_cost_change()           SET search_path TO 'public';
ALTER FUNCTION public.recalc_po_total(uuid)               SET search_path TO 'public';
ALTER FUNCTION public.set_ai_agent_memory_updated_at()    SET search_path TO 'public';
ALTER FUNCTION public.set_ai_agent_tasks_updated_at()     SET search_path TO 'public';
ALTER FUNCTION public.set_ai_inbound_sessions_updated_at() SET search_path TO 'public';
ALTER FUNCTION public.set_ai_workflows_updated_at()       SET search_path TO 'public';
ALTER FUNCTION public.touch_fiscal_emission_draft()       SET search_path TO 'public';
ALTER FUNCTION public.trg_poi_recalc_total()              SET search_path TO 'public';
ALTER FUNCTION public.update_updated_at_column()          SET search_path TO 'public';
ALTER FUNCTION public.wa_normalize_phone(text)            SET search_path TO 'public';
