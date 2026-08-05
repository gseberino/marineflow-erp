-- ═══════════════════════════════════════════════════════════════════════════
-- A descrição do orçamento passa a valer alguma coisa
--
-- Hoje o dono escreve "Substituir as baterias para sistema lifepo4, trocar os
-- cabos em acordo com o dimensionamento, crimpar terminais novos, colocar
-- dispositivos de proteção nos circuitos" — e o único botão de IA em cima
-- desse texto reescreve a redação. O texto já diz o verbo, o sistema e metade
-- das respostas do levantamento, e ninguém lê.
--
-- Estas duas funções são a ponte. Nenhuma delas fala com IA: uma entrega o
-- catálogo de perguntas para a IA ler, a outra monta o questionário a partir
-- dos eixos que a IA devolveu. A decisão de o que perguntar continua sendo do
-- catálogo aprovado — a IA escolhe o EIXO, nunca inventa a PERGUNTA.
--
-- Por que isso importa: pergunta inventada na hora não tem impacto no preço
-- declarado, não entra no histórico do ativo e não dispara regra de material.
-- Ela vira texto solto e morre ali. As 78 aprovadas fazem as três coisas.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. O catálogo compacto, para caber num prompt
--
-- Só o que a IA precisa para decidir eixo e pré-responder. Sem help_text, sem
-- histórico: cada caractere aqui é pago em toda análise de descrição.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.survey_question_catalog()
returns table (
  id uuid,
  eixo text,
  tipo_eixo text,
  question text,
  answer_type text,
  options jsonb,
  price_impact text)
language sql stable security invoker set search_path = public
as $fn$
  select t.id,
         coalesce(t.applies_to_system, t.applies_to_verb),
         case when t.applies_to_system is not null then 'sistema' else 'verbo' end,
         t.question, t.answer_type, t.options, t.price_impact
  from public.service_survey_templates t
  where t.active
    and t.service_id is null          -- as de serviço específico não compõem por eixo
    and coalesce(t.applies_to_system, t.applies_to_verb) is not null
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end, t.seq;
$fn$;

revoke all on function public.survey_question_catalog() from public, anon;
grant execute on function public.survey_question_catalog() to authenticated;

comment on function public.survey_question_catalog() is
  'Catálogo enxuto das perguntas por eixo, para caber num prompt de análise de
   descrição. A IA escolhe entre estas — não inventa pergunta nova.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. O questionário a partir dos eixos
--
-- Mesma regra da composição por serviço (ordem por impacto no preço, teto de
-- 9), só que entrando pelos eixos em vez do serviço. É o que permite levantar
-- antes de escolher o serviço — e a descrição é escrita antes de tudo.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.compose_survey_for_axes(
  p_system text default null,
  p_verb text default null,
  p_mode text default 'local')
returns table (
  id uuid,
  seq integer,
  question text,
  help_text text,
  answer_type text,
  options jsonb,
  price_impact text,
  ask_remotely boolean,
  origem text)
language plpgsql stable security invoker set search_path = public
as $fn$
begin
  if p_system is null and p_verb is null then
    return;  -- sem eixo não há o que compor; devolver tudo seria pior que nada
  end if;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.applies_to_system is not null then 'sistema' else 'verbo' end
  from public.service_survey_templates t
  where t.active
    and (p_mode <> 'remoto' or t.ask_remotely)
    and (
         (p_system is not null and t.applies_to_system = p_system)
      or (p_verb   is not null and t.applies_to_verb   = p_verb)
    )
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           t.seq
  limit 9;
end;
$fn$;

revoke all on function public.compose_survey_for_axes(text, text, text) from public, anon;
grant execute on function public.compose_survey_for_axes(text, text, text) to authenticated;

comment on function public.compose_survey_for_axes(text, text, text) is
  'Questionário a partir do sistema e/ou verbo, sem depender de serviço
   escolhido — a descrição do orçamento vem antes da escolha do serviço.';
