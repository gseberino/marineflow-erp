-- ═══════════════════════════════════════════════════════════════════════════
-- `lines_missing_system` passa a dizer o que JÁ ESTÁ GRAVADO na linha
--
-- ═══ POR QUE ISTO É PRÉ-REQUISITO DO BOTÃO CONFIRMAR ═══
--
-- A RPC devolvia sete colunas e nenhuma era o `service_system` atual da linha.
-- `sistema_sugerido` é SEMPRE um palpite recalculado
-- (`coalesce(sis_da_linha, sis_da_os)`), independente do que já foi gravado.
--
-- Repare na assimetria que existia: para o VERBO a função devolve o valor real
-- (`coalesce(sos.service_verb, s.service_verb)` na coluna `service_verb`); para
-- o SISTEMA, não havia equivalente.
--
-- Isso importa porque o filtro aceita a linha quando falta QUALQUER um dos dois
-- eixos. Uma linha que já tem `service_system` salvo mas está sem verbo entra na
-- lista — e a tela mostrava o Select de sistema preenchido com o PALPITE, sob a
-- legenda "sugerido pelo texto desta linha". Se o palpite discordasse do banco,
-- confirmar sobrescrevia uma classificação correta que já existia.
--
-- Com `sistema_atual`, a tela mostra o que está gravado quando há algo gravado,
-- e o palpite só aparece onde não há nada. O Confirmar deixa de ser um risco.
--
-- Trocar o tipo de retorno exige derrubar antes: o Postgres recusa
-- `create or replace` quando as colunas de saída mudam.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

drop function if exists public.lines_missing_system(uuid);

create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (
  line_id uuid,
  service_name text,
  service_verb text,
  /* O que está GRAVADO para o sistema — da linha, ou herdado do catálogo.
     Nulo significa "ninguém definiu", e só aí o palpite deve aparecer. */
  sistema_atual text,
  sistema_sugerido text,
  verbo_sugerido text,
  origem_sistema text,
  origem_verbo text)
language sql stable set search_path to 'public', 'extensions'
as $fn$
  with base as (
    select
      sos.id,
      sos.name_snapshot,
      coalesce(sos.service_verb, s.service_verb) as verbo_atual,
      coalesce(sos.service_system, s.service_system) as sistema_gravado,
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
    sistema_gravado,
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

comment on function public.lines_missing_system(uuid) is
  'Linhas da ordem em que falta pelo menos um dos dois eixos de classificação.
   Devolve o que está GRAVADO (sistema_atual, service_verb) e, à parte, o
   PALPITE (sistema_sugerido, verbo_sugerido) com a procedência de cada um — a
   tela precisa saber a diferença para não oferecer um palpite por cima de uma
   classificação que já existe.';

commit;
