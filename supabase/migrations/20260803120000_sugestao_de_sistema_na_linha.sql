-- ═══════════════════════════════════════════════════════════════════════════
-- Sugestão de sistema para a linha de serviço genérico
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27-P28)
--
-- Pedido do dono (03/08): serviços como "diagnóstico técnico no local" servem a
-- vários sistemas, e é a escolha na OS que muda o roteiro — assim não precisa de
-- um cadastro por categoria. Ele está certo, e isso já funcionava; o que faltava
-- era pedir a escolha na hora certa e não deixar o campo vazio esperando que
-- alguém lembre.
--
-- POR QUE IMPORTA ALÉM DO ROTEIRO: o sistema muda o TEMPO PREVISTO, e portanto o
-- preço. "Diagnóstico técnico no local" sai com 1h45 sem sistema; com hidráulico
-- vai a 3h10, com gás a 3h25, com elétrico DC a 3h45 — mais que o dobro. Um
-- orçamento fechado antes dessa escolha subestima o trabalho.
--
-- A sugestão tem duas fontes, nesta ordem:
--   1. O problema relatado na OS, lido pela mesma regra de palavra-chave que
--      classifica o catálogo (`classify_service_text`) — que, aliás, existia e
--      não era chamada por ninguém desde que foi escrita.
--   2. As outras linhas da OS: se três serviços são de elétrico DC, o
--      diagnóstico provavelmente também é.
--
-- E ela é SUGESTÃO, nunca preenchimento silencioso. Nos testes com as OS reais
-- ela acertou "Passarela Hidráulica" → hidráulico e "Sistema Elétrico DC 12V" →
-- elétrico DC, mas não reconhece "Diagnóstico Radar" (a regra conhece "rádio" e
-- não "radar") e se confunde quando o texto fala de dois sistemas. Por isso o
-- campo aparece preenchido, visível e editável — quem confirma é gente.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.suggest_system_for_line(p_line_id uuid)
returns table (sistema text, motivo text)
language sql stable security invoker set search_path = public, extensions
as $fn$
  with linha as (
    select sos.id, sos.service_order_id, so.problem_description
    from public.service_order_services sos
    join public.service_orders so on so.id = sos.service_order_id
    where sos.id = p_line_id
  ),
  pelo_texto as (
    select ss.slug as sis, 'pelo problema relatado nesta OS' as motivo
    from linha l
    join public.service_systems ss
      on ss.slug = (public.classify_service_text(l.problem_description)->>'sistema')
    where ss.is_physical and ss.active
  ),
  pelas_irmas as (
    select ss.slug as sis,
           'as outras linhas desta OS são de ' || coalesce(ss.short_name, ss.name) as motivo
    from linha l
    join public.service_order_services sos
      on sos.service_order_id = l.service_order_id and sos.id <> l.id
    join public.services s on s.id = sos.service_id
    join public.service_systems ss
      on ss.slug = coalesce(sos.service_system, s.service_system)
    where ss.is_physical and ss.active
    group by ss.slug, ss.short_name, ss.name
    order by count(*) desc, ss.slug
    limit 1
  )
  select sis, motivo from pelo_texto
  union all
  select sis, motivo from pelas_irmas where not exists (select 1 from pelo_texto)
  limit 1;
$fn$;

revoke all on function public.suggest_system_for_line(uuid) from public, anon;
grant execute on function public.suggest_system_for_line(uuid) to authenticated;
