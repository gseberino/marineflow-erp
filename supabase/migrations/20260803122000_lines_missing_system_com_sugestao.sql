-- ═══════════════════════════════════════════════════════════════════════════
-- A lista de linhas sem sistema passa a trazer a sugestão junto
--
-- A tela precisa da sugestão para já deixar o campo preenchido. Pedir linha a
-- linha seriam N chamadas para montar um aviso; uma consulta só resolve.
--
-- Continua SECURITY INVOKER: a função apenas lê o que a RLS já permite ao
-- usuário — foi o conserto de 02/08, quando eu a tinha escrito como DEFINER
-- por hábito e ela ignorava RLS.
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists public.lines_missing_system(uuid);

create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (
  line_id uuid,
  service_name text,
  service_verb text,
  sistema_sugerido text,
  motivo_sugestao text)
language sql stable security invoker set search_path = public, extensions
as $fn$
  select sos.id, sos.name_snapshot, s.service_verb, sug.sistema, sug.motivo
  from public.service_order_services sos
  join public.services s on s.id = sos.service_id
  left join lateral public.suggest_system_for_line(sos.id) sug on true
  where sos.service_order_id = p_service_order_id
    and sos.service_system is null
    and s.service_system is null
    and not exists (select 1 from public.service_step_templates t
                    where t.service_id = sos.service_id and t.active);
$fn$;

revoke all on function public.lines_missing_system(uuid) from public, anon;
grant execute on function public.lines_missing_system(uuid) to authenticated;
