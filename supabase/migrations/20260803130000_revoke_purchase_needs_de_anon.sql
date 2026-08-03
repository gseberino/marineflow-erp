-- ─────────────────────────────────────────────────────────────────────────────
-- Fecha de verdade o acesso de anon às funções de necessidade de compra.
--
-- As migrations anteriores faziam `revoke all on function ... from public` e
-- ISSO NÃO BASTA neste projeto. O Supabase mantém um ALTER DEFAULT PRIVILEGES
-- que concede EXECUTE **nominalmente** a anon em toda função nova do schema
-- public — o proacl da função nasce como:
--     {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- Revogar de PUBLIC remove só o grant implícito de PUBLIC; o grant nominal de
-- anon continua de pé. Só se fecha revogando de anon POR NOME.
--
-- Como conferir (não confie no revoke ter funcionado — verifique):
--     select has_function_privilege('anon', 'public.get_os_purchase_needs(uuid)', 'execute');
-- Tem de devolver false.
--
-- Impacto real era limitado, porque get_os_purchase_needs é security invoker e a
-- RLS das tabelas de compras já barra anon — mas defesa em profundidade é o
-- ponto: a função lê custo de aquisição, restrito a admin/financeiro.
-- ─────────────────────────────────────────────────────────────────────────────

revoke all on function public.get_os_purchase_needs(uuid) from anon;
revoke all on function public.compute_purchase_needs(uuid, jsonb, jsonb, jsonb, jsonb) from anon;
