-- ═══════════════════════════════════════════════════════════════════════════
-- Com dois trechos medidos, o cabo passa a sair pelo MAIS LONGO — e diz isso
--
-- ═══ O QUE ESTAVA ACONTECENDO ═══
--
-- Existem duas perguntas ativas com papel `comprimento`: "distância do banco de
-- baterias até o inversor" e "distância do inversor (ou banco) até o quadro de
-- distribuição". A segunda é justamente o conserto do ORÇ-00074, onde a pergunta
-- pedia dois trechos e tinha um campo só.
--
-- Só que `survey_cable_sizing` lia o comprimento com `order by answered_at desc
-- limit 1` — pegava UM, o respondido por último. O técnico media os dois
-- percursos e o cabo saía dimensionado por um deles, possivelmente o CURTO. E
-- desde 19/08 esse número escolhe o produto que entra no orçamento.
--
-- ═══ POR QUE O MAIS LONGO, E NÃO A SOMA ═══
--
-- Somar seria inventar: os trechos são circuitos diferentes, não parcelas de um
-- percurso. Cada um pede o seu cabo, e o certo é dimensionar UM POR TRECHO —
-- que é a mudança maior, e continua registrada como o destino.
--
-- Até lá, o mais longo é a única escolha que não subdimensiona nenhum dos dois:
-- o cabo que atende o percurso comprido atende o curto com folga. Erra para
-- cima, custa mais caro, e não esquenta. O contrário não era verdade.
--
-- E passa a DIZER: quantos trechos foram medidos, e que a conta usou o maior.
-- Número conservador apresentado sem a premissa é o mesmo problema de sempre.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

create or replace function public.survey_cable_sizing(p_survey_id uuid)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v jsonb; v_amps numeric; v_len numeric; v_volts numeric := 12;
  v_drop numeric := 3; v_engine boolean := false; v_bundle integer := 1;
  v_txt text; v_trechos integer := 0; v_menor numeric; v_aviso text;
begin
  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_amps
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'corrente' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

  -- O MAIOR dos trechos medidos, e quantos são. Antes era `limit 1` pela
  -- resposta mais recente, o que dependia da ordem em que o técnico respondeu.
  select max(coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))),
         min(coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))),
         count(*)
    into v_len, v_menor, v_trechos
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'comprimento' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null);

  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'tensao' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  if v_txt is not null then v_volts := coalesce(public.parse_answer_number(v_txt), 12); end if;

  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'criticidade' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  if v_txt is not null and v_txt ilike '%não crítico%' then v_drop := 10; end if;

  select lower(trim(a.answer_value)) in ('sim','s','true') into v_engine
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'casa_maquinas' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value), 1)::integer
    into v_bundle
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'feixe' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

  v := public.dc_cable_sizing(v_amps, v_len, v_volts, v_drop, 90,
                              coalesce(v_engine, false), coalesce(v_bundle, 1));

  -- A premissa vai junto do número, no mesmo campo que o agente é instruído a
  -- repetir. Deixá-la só numa chave à parte seria contar com alguém a procurar.
  if coalesce(v_trechos, 0) > 1 then
    v_aviso := 'Foram medidos ' || v_trechos || ' trechos (do menor ' || v_menor
            || ' m ao maior ' || v_len || ' m). A conta usou o MAIS LONGO, que é o '
            || 'único que não subdimensiona nenhum dos dois — mas cada percurso é '
            || 'um circuito e pede o seu próprio cabo. Confira se um cabo só atende.';
    v := jsonb_set(v, '{aviso}',
           to_jsonb(concat_ws(' ', nullif(v->>'aviso', ''), v_aviso)));
  end if;

  return v || jsonb_build_object(
    'trechos_medidos', coalesce(v_trechos, 0),
    'lido_do_levantamento', jsonb_build_object(
      'corrente_a', v_amps, 'trecho_m', v_len,
      'trecho_criterio', case when coalesce(v_trechos,0) > 1
                              then 'o mais longo de ' || v_trechos || ' medidos'
                              else 'único trecho medido' end,
      'tensao_v', v_volts,
      'queda_max_pct', v_drop, 'casa_de_maquinas', coalesce(v_engine, false),
      'condutores_no_feixe', coalesce(v_bundle, 1)));
end;
$fn$;

revoke all on function public.survey_cable_sizing(uuid) from public, anon;
grant execute on function public.survey_cable_sizing(uuid) to authenticated;

comment on function public.survey_cable_sizing(uuid) is
  'Dimensiona o cabo a partir das respostas do levantamento. Com mais de um
   trecho medido, usa o MAIS LONGO e declara isso no aviso e em
   lido_do_levantamento.trecho_criterio — é a escolha que não subdimensiona
   nenhum percurso. Dimensionar um cabo POR TRECHO continua sendo o destino
   (NOVO-lev-36); isto é a saída segura enquanto lá não se chega.';

commit;
