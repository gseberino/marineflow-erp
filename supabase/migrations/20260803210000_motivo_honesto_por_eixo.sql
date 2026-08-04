-- ═══════════════════════════════════════════════════════════════════════════
-- O motivo da sugestão passa a dizer a verdade sobre cada eixo
--
-- Ao testar na OS-00061 apareceram três linhas com sistema sugerido "gás" sem
-- nenhuma razão visível — "Sikaflex 221", "Conduíte corrugado". O sistema tinha
-- vindo do palpite da OS (o problema relatado fala de gás), mas o motivo na tela
-- dizia "pelo texto desta linha", porque eu montei a frase olhando se QUALQUER
-- um dos dois eixos veio do texto.
--
-- Motivo confiante em cima de sugestão fraca é pior que sugestão sem motivo:
-- convida a confirmar sem ler. Agora cada eixo carrega a própria origem, e
-- quando o sistema veio do contexto da OS a tela pode dizer isso com todas as
-- letras — inclusive "não sei, escolha você".
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists public.lines_missing_system(uuid);

create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (
  line_id uuid,
  service_name text,
  service_verb text,
  sistema_sugerido text,
  verbo_sugerido text,
  origem_sistema text,   -- 'linha' | 'os' | null
  origem_verbo text)     -- 'linha' | null
language sql stable security invoker set search_path = public, extensions
as $fn$
  with base as (
    select
      sos.id,
      sos.name_snapshot,
      coalesce(sos.service_verb, s.service_verb) as verbo_atual,
      sos.service_id,
      -- o que o texto da própria linha diz
      (select ss.slug from public.service_systems ss
        where ss.slug = (public.classify_service_text(sos.name_snapshot)->>'sistema')
          and ss.is_physical and ss.active) as sis_da_linha,
      (select sv.slug from public.service_verbs sv
        where sv.slug = (public.classify_service_text(sos.name_snapshot)->>'verbo')
          and sv.active) as verbo_da_linha,
      -- e o que o contexto da OS sugere, como segunda opção
      (select sug.sistema from public.suggest_system_for_line(sos.id) sug) as sis_da_os
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and (
        (sos.service_system is null and s.service_system is null)
        or (sos.service_verb is null and s.service_verb is null)
      )
      and not exists (select 1 from public.service_step_templates t
                      where t.service_id = sos.service_id and t.active)
  )
  select
    id, name_snapshot, verbo_atual,
    coalesce(sis_da_linha, sis_da_os),
    verbo_da_linha,
    case when sis_da_linha is not null then 'linha'
         when sis_da_os is not null then 'os'
         else null end,
    case when verbo_da_linha is not null then 'linha' else null end
  from base;
$fn$;

revoke all on function public.lines_missing_system(uuid) from public, anon;
grant execute on function public.lines_missing_system(uuid) to authenticated;
