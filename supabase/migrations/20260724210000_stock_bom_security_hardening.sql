-- Endurecimento de segurança dos objetos criados (produto pendente/fiscal, preço, BOM, estoque v2),
-- guiado pelos advisors do Supabase:
--  1) a view product_availability deve respeitar a RLS de QUEM consulta (security_invoker);
--  2) fixar search_path da trigger de completude fiscal;
--  3) funções nascem com EXECUTE para PUBLIC — trancar as internas (as triggers as chamam como
--     SECURITY DEFINER, sem depender de grant público). Só resolve_practiced_price (usada pela UI)
--     e reconcile_stock_to_v2 (ops) mantêm grant explícito.

-- 1) View respeita a RLS do chamador (cliente por share-token vê só o seu; agente/equipe veem tudo).
alter view public.product_availability set (security_invoker = on);

-- 2) search_path fixo na trigger de completude fiscal.
alter function public.compute_product_fiscal_complete() set search_path to 'public';

-- 3) Trancar EXECUTE (inclui grants explícitos anteriores a anon/authenticated) nas funções
--    internas. As triggers as chamam como SECURITY DEFINER (contexto do dono), sem depender disso.
revoke all on function public.stock_model_v2_on()                  from public, anon, authenticated;
revoke all on function public.recompute_product_reservations(uuid) from public, anon, authenticated;
revoke all on function public.recompute_product_cost(uuid)         from public, anon, authenticated;
revoke all on function public.reconcile_stock_to_v2()              from public, anon, authenticated;
revoke all on function public.trg_parts_reservation()             from public, anon, authenticated;
revoke all on function public.trg_so_status_stock()               from public, anon, authenticated;
revoke all on function public.trg_product_components_rollup()     from public, anon, authenticated;
revoke all on function public.compute_product_fiscal_complete()   from public, anon, authenticated;

-- reconcile é operação de virada — só service_role.
grant execute on function public.reconcile_stock_to_v2() to service_role;

-- resolve_practiced_price: usada pela UI (authenticated) e pelo agente (service_role), NÃO por anon.
revoke all on function public.resolve_practiced_price(uuid, uuid) from public, anon;
grant execute on function public.resolve_practiced_price(uuid, uuid) to authenticated, service_role;
