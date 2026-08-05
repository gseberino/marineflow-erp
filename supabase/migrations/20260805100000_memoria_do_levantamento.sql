-- ═══════════════════════════════════════════════════════════════════════════
-- O levantamento passa a lembrar do ativo
--
-- Levantar o mesmo motorhome daqui a seis meses hoje recomeça do zero — e
-- metade das perguntas tem a mesma resposta de sempre: onde fica o cilindro,
-- qual a distância do banco ao quadro, se há detector de gás. Perguntar de novo
-- o que já se sabe gasta o tempo de quem responde e ensina que o levantamento é
-- burocracia.
--
-- A memória é do ATIVO, não do cliente: o cilindro fica no mesmo lugar do
-- mesmo motorhome, independentemente de quem o comprou depois.
--
-- Só entra resposta de levantamento FECHADO. Resposta de rascunho pode ser um
-- meio-caminho que alguém abandonou, e sugerir isso como "da última vez" seria
-- propagar uma informação que ninguém confirmou.
--
-- A data vai junto de propósito: resposta de dois anos atrás merece
-- desconfiança, e quem está em campo é que sabe se ainda vale.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.previous_survey_answers(p_vessel_id uuid)
returns table (
  template_id uuid,
  question text,
  answer text,
  answered_at timestamptz,
  service_order_number text)
language sql stable security invoker set search_path = public
as $fn$
  -- distinct on (template_id) + order by answered_at desc = a resposta MAIS
  -- RECENTE de cada pergunta. Respostas antigas do mesmo item ficam de fora:
  -- oferecer três versões da mesma coisa transferiria a decisão para quem só
  -- queria uma dica.
  select distinct on (a.template_id)
    a.template_id,
    a.question_snapshot,
    a.answer_value,
    a.answered_at,
    so.service_order_number
  from public.service_survey_answers a
  join public.service_surveys s on s.id = a.survey_id
  left join public.service_orders so on so.id = s.service_order_id
  where s.vessel_id = p_vessel_id
    and s.status = 'closed'
    and a.template_id is not null
    and a.answer_value is not null
    and a.skipped_reason is null
  order by a.template_id, a.answered_at desc nulls last;
$fn$;

revoke all on function public.previous_survey_answers(uuid) from public, anon;
grant execute on function public.previous_survey_answers(uuid) to authenticated;

comment on function public.previous_survey_answers(uuid) is
  'Última resposta de cada pergunta já levantada NESTE ativo, de levantamentos
   fechados. Serve para não perguntar de novo o que não muda — com a data à
   vista, porque quem decide se ainda vale é quem está no local.';
