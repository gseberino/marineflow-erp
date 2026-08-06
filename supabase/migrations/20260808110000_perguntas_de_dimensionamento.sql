-- ═══════════════════════════════════════════════════════════════════════════
-- As perguntas que a ABYC E-11 e a Blue Sea exigem para dimensionar um cabo
--
-- Não dá para dimensionar cabo com distância e olho. As duas referências
-- pedem, no mínimo: corrente, comprimento, tensão do sistema, e se o circuito
-- é crítico (3% de queda) ou não (10%). Para a ampacidade entram ainda a
-- isolação do condutor, se passa por casa de máquinas e quantos condutores vão
-- no mesmo feixe.
--
-- O levantamento já perguntava duas dessas (corrente e distância). Faltavam
-- quatro. Entram INATIVAS, como toda pergunta nova.
--
-- A COLUNA `affects` FINALMENTE SERVE PARA ALGO. Ela existia desde o início e
-- estava vazia nas 78 perguntas — fui eu que escrevi as 78 e deixei em branco.
-- Agora ela marca o PAPEL da resposta no cálculo, e é por ela que o
-- dimensionador acha o que precisa. Sem isso, seria casar pergunta por texto,
-- que quebra no dia em que alguém reescrever o enunciado.
-- ═══════════════════════════════════════════════════════════════════════════

-- As duas que já existem passam a declarar o papel que sempre tiveram.
update public.service_survey_templates
set affects = array['corrente']
where applies_to_system = 'eletrico_dc'
  and question ilike '%corrente máxima do circuito%'
  and (affects is null or cardinality(affects) = 0);

update public.service_survey_templates
set affects = array['comprimento']
where applies_to_system = 'eletrico_dc'
  and question ilike '%distância entre o banco%'
  and (affects is null or cardinality(affects) = 0);

-- As quatro que faltavam.
insert into public.service_survey_templates
  (service_id, seq, question, help_text, answer_type, options, price_impact,
   ask_remotely, origin, active, applies_to_system, affects, version)
select * from (values
  (null::uuid, 13,
   'Qual a tensão do sistema?',
   'A mesma corrente em 24 V pede metade da bitola que em 12 V. É o primeiro '
   'dado de qualquer tabela de dimensionamento.',
   'escolha', '["12 V","24 V","48 V"]'::jsonb, 'alto',
   false, 'ai', false, 'eletrico_dc', array['tensao'], 1),

  (null::uuid, 14,
   'Este circuito é crítico?',
   'A ABYC aceita no máximo 3% de queda de tensão em circuito crítico — o que '
   'alimenta navegação, bomba de porão, e os alimentadores principais. Até 10% '
   'em circuito não crítico, como iluminação de cabine. A diferença entre 3% e '
   '10% chega a triplicar a bitola.',
   'escolha', '["crítico (3%)","não crítico (10%)"]'::jsonb, 'alto',
   false, 'ai', false, 'eletrico_dc', array['criticidade'], 1),

  (null::uuid, 15,
   'O cabo passa por casa de máquinas ou compartimento de motor?',
   'Ambiente quente derrata a ampacidade: o mesmo cabo aguenta menos corrente. '
   'Conferir o fator na ABYC E-11 — ele muda conforme a isolação.',
   'sim_nao', null, 'medio',
   false, 'ai', false, 'eletrico_dc', array['casa_maquinas'], 1),

  (null::uuid, 16,
   'Quantos condutores vão no mesmo feixe ou conduíte?',
   'Cabos amarrados juntos não dissipam calor como um cabo solto, e a norma '
   'manda derratar conforme a quantidade. Conte os que ficam no mesmo feixe.',
   'numero', null, 'medio',
   false, 'ai', false, 'eletrico_dc', array['feixe'], 1)
) as novas(service_id, seq, question, help_text, answer_type, options, price_impact,
           ask_remotely, origin, active, applies_to_system, affects, version)
where not exists (
  select 1 from public.service_survey_templates t
  where t.applies_to_system = 'eletrico_dc'
    and t.question = novas.question);

-- ───────────────────────────────────────────────────────────────────────────
-- O dimensionamento a partir do que o levantamento respondeu
--
-- Lê as respostas pelos PAPÉIS (affects), não pelo texto da pergunta, e chama
-- o dimensionador. Devolve também o que ficou faltando: é essa lista que faz a
-- tela pedir a resposta certa em vez de dar um número inventado.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.survey_cable_sizing(p_survey_id uuid)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v jsonb; v_amps numeric; v_len numeric; v_volts numeric := 12;
  v_drop numeric := 3; v_engine boolean := false; v_bundle integer := 1;
  v_txt text;
begin
  -- Um SELECT por papel. A resposta mais recente ganha, porque corrigir uma
  -- resposta é o caminho normal desde que o levantamento fechado voltou a ser
  -- editável.
  select public.parse_answer_number(a.answer_value) into v_amps
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'corrente' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  select public.parse_answer_number(a.answer_value) into v_len
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'comprimento' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'tensao' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  if v_txt is not null then
    v_volts := coalesce(public.parse_answer_number(v_txt), 12);
  end if;

  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'criticidade' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  -- Na dúvida fica 3%: o lado seguro é o cabo mais grosso. Assumir 10% por
  -- omissão subdimensionaria em silêncio.
  if v_txt is not null and v_txt ilike '%não crítico%' then v_drop := 10; end if;

  select lower(trim(a.answer_value)) in ('sim','s','true') into v_engine
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'casa_maquinas' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  select coalesce(public.parse_answer_number(a.answer_value), 1)::integer into v_bundle
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'feixe' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  v := public.dc_cable_sizing(v_amps, v_len, v_volts, v_drop, 105,
                              coalesce(v_engine, false), coalesce(v_bundle, 1));

  return v || jsonb_build_object('lido_do_levantamento', jsonb_build_object(
    'corrente_a', v_amps, 'trecho_m', v_len, 'tensao_v', v_volts,
    'queda_max_pct', v_drop, 'casa_de_maquinas', coalesce(v_engine, false),
    'condutores_no_feixe', coalesce(v_bundle, 1)));
end;
$fn$;

revoke all on function public.survey_cable_sizing(uuid) from public, anon;
grant execute on function public.survey_cable_sizing(uuid) to authenticated;

comment on function public.survey_cable_sizing(uuid) is
  'Dimensiona o cabo com o que o levantamento respondeu, casando pelos papéis
   em service_survey_templates.affects. Queda máxima assume 3% quando a
   criticidade não foi respondida — o lado seguro é o cabo mais grosso.';
