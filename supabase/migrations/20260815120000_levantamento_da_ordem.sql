-- ═══════════════════════════════════════════════════════════════════════════
-- O levantamento passa a ser DA ORDEM, não de um serviço
--
-- O dono descreveu o fluxo real da visita técnica:
--
--   "quando não há um serviço determinado e exige avaliação no local, o
--    orçamento parte do princípio de conter no mínimo o deslocamento e o
--    serviço de diagnóstico/avaliação — e então atualiza ou gera um novo
--    orçamento a partir deste."
--
-- E o que falta para isso funcionar: "o técnico precisa responder o que será
-- avaliado, e o sistema deverá gerar um escopo de perguntas que faça sentido
-- ao contexto".
--
-- ═══ O QUE ESTAVA QUEBRADO ═══
--
-- "DIAGNÓSTICO TÉCNICO NO LOCAL" tem sistema NULO — é genérico de propósito,
-- porque numa visita de avaliação ainda não se sabe o que será avaliado. A
-- composição por serviço então achava só 3 perguntas, as do verbo
-- `diagnostico`. Nenhuma de elétrico, de gás ou de refrigeração — justamente as
-- que dizem o que medir.
--
-- ═══ A MUDANÇA ═══
--
-- O levantamento pertence à ORDEM, não a um serviço: `service_surveys` já
-- aponta para `service_order_id`. Um orçamento com três serviços precisa
-- levantar o necessário para os três, e uma visita de avaliação precisa
-- levantar o dos sistemas que o técnico marcou nas linhas.
--
-- O sistema de cada linha já existe (`service_order_services.service_system`),
-- e já é escolhido na tela quando o serviço é genérico. É dele que sai o
-- escopo.
--
-- ═══ POR QUE RODÍZIO, E NÃO OS 12 MAIS IMPORTANTES ═══
--
-- Ordenar tudo por impacto e cortar em 12 faria um sistema "forte" — o elétrico
-- DC, com nove perguntas de impacto alto — engolir a lista inteira, e o gás da
-- mesma visita ficaria sem nenhuma. O rodízio pega a mais importante de CADA
-- eixo antes de pegar a segunda de qualquer um: com três sistemas na ordem,
-- todos aparecem antes de qualquer um se repetir.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.compose_survey_for_order(
  p_service_order_id uuid,
  p_mode text default 'local',
  p_limit integer default 12)
returns table (
  id uuid,
  seq integer,
  question text,
  help_text text,
  answer_type text,
  options jsonb,
  price_impact text,
  ask_remotely boolean,
  origem text,
  expected_unit text,
  min_expected numeric,
  max_expected numeric,
  /* De qual eixo esta pergunta veio. A folha agrupa por isto — "vou avaliar o
     elétrico e o gás" fica legível quando as perguntas vêm separadas por
     sistema, e não embaralhadas por impacto. */
  eixo text)
language plpgsql stable security invoker set search_path = public
as $fn$
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  return query
  with eixos as (
    -- O sistema da LINHA ganha do sistema do catálogo: é ele que o técnico
    -- escolheu para esta visita. O do catálogo entra quando a linha não diz.
    select distinct
      coalesce(sos.service_system, s.service_system) as sistema,
      s.service_verb as verbo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
  ),
  candidatas as (
    select t.*, coalesce(t.applies_to_system, t.applies_to_verb) as eixo_da_pergunta
    from public.service_survey_templates t
    where t.active
      and t.service_id is null
      and (p_mode <> 'remoto' or t.ask_remotely)
      and exists (
        select 1 from eixos e
        where (t.applies_to_system is not null and t.applies_to_system = e.sistema)
           or (t.applies_to_verb   is not null and t.applies_to_verb   = e.verbo)
      )
  ),
  ordenadas as (
    select c.*,
      -- Posição dentro do próprio eixo, por impacto no preço.
      row_number() over (
        partition by c.eixo_da_pergunta
        order by case c.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
                 c.seq
      ) as posicao_no_eixo
    from candidatas c
  )
  select o.id, o.seq, o.question, o.help_text, o.answer_type, o.options,
         o.price_impact, o.ask_remotely,
         case when o.applies_to_system is not null then 'sistema' else 'verbo' end,
         o.expected_unit, o.min_expected, o.max_expected,
         o.eixo_da_pergunta
  from ordenadas o
  -- Rodízio: todas as primeiras de cada eixo, depois todas as segundas.
  order by o.posicao_no_eixo,
           case o.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           o.eixo_da_pergunta, o.seq
  limit greatest(coalesce(p_limit, 12), 1);
end;
$fn$;

revoke all on function public.compose_survey_for_order(uuid, text, integer) from public, anon;
grant execute on function public.compose_survey_for_order(uuid, text, integer) to authenticated;

comment on function public.compose_survey_for_order(uuid, text, integer) is
  'Questionário de uma ORDEM inteira, a partir dos sistemas e verbos de todas as
   suas linhas. É o que permite levantar numa visita de avaliação, onde o
   serviço é genérico ("diagnóstico no local") e quem diz o que será avaliado é
   o técnico, marcando o sistema em cada linha. Rodízio entre eixos para que
   nenhum sistema da visita fique sem pergunta.';
