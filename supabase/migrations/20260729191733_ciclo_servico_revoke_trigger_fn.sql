-- Apontado pelo advisor logo após a migration do Ciclo do Serviço.
--
-- rollup_step_time_to_service_line() é função de TRIGGER e precisa ser
-- SECURITY DEFINER (escreve em service_order_services independentemente da RLS
-- de quem move o passo). O efeito colateral é que o PostgREST a expõe em
-- /rest/v1/rpc/ — inclusive para anon. Chamada fora do contexto de trigger ela
-- falharia, mas superfície que não precisa existir não deve existir. Mesmo
-- endurecimento já aplicado às demais funções em 20260728010752.
revoke all on function public.rollup_step_time_to_service_line() from public, anon, authenticated;
