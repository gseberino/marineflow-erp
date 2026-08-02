-- ═══════════════════════════════════════════════════════════════════════════
-- Correção de segurança: lines_missing_system não podia ser SECURITY DEFINER
--
-- Escrevi a função como SECURITY DEFINER por hábito, copiando o padrão das
-- vizinhas — mas as vizinhas que precisam de DEFINER GRAVAM (e por isso
-- carregam a checagem de is_external_seller na primeira linha). Esta só lê.
--
-- DEFINER sem checagem = RLS ignorada: um vendedor externo autenticado poderia
-- chamar /rest/v1/rpc/lines_missing_system com o id de qualquer OS e enumerar
-- os serviços dela. Mesma classe do problema de rollup_step_time_to_service_line
-- em 29/07.
--
-- INVOKER é a resposta certa aqui: a função lê apenas o que a RLS já permite
-- àquele usuário, e nada precisa ser checado à mão.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (line_id uuid, service_name text, service_verb text)
language sql stable security invoker set search_path = public as $fn$
  select sos.id, sos.name_snapshot, s.service_verb
  from public.service_order_services sos
  join public.services s on s.id = sos.service_id
  where sos.service_order_id = p_service_order_id
    and sos.service_system is null
    and s.service_system is null
    and not exists (select 1 from public.service_step_templates t
                    where t.service_id = sos.service_id and t.active);
$fn$;

revoke all on function public.lines_missing_system(uuid) from public, anon;
grant execute on function public.lines_missing_system(uuid) to authenticated;
