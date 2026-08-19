-- ═══════════════════════════════════════════════════════════════════════════
-- O dimensionamento passa a avisar quando o número que ele usou é ambíguo
--
-- ═══ COMO ISTO APARECEU ═══
--
-- Ao rodar o levantamento real do ORÇ-00074 de ponta a ponta, a resposta do
-- comprimento é esta, literal:
--
--   "Entre o banco de baterias e o inversor, o caminho que o cabo positivo faz
--    é de aproximadamente 2,5 metros. E até o quadro de disjuntores e é de
--    2 metros."
--
-- Dois trechos, uma resposta só — o caso que deu origem a toda esta frente. O
-- `parse_answer_number` lê o PRIMEIRO número (2,5) e ignora o resto, e
-- `survey_cable_sizing` respondia `pronto: true` sem dizer nada.
--
-- `survey_suggested_materials` SEMPRE avisou disso ("a resposta tem mais de um
-- número: usei o primeiro"). O dimensionamento, não. Enquanto ele só produzia um
-- número na tela, a assimetria era tolerável; desde 19/08 esse número ESCOLHE O
-- CABO que entra no orçamento, e o aviso precisa estar nos dois lugares.
--
-- Nota sobre o alcance: isto NÃO desambigua a resposta — só para de esconder que
-- ela é ambígua. Quem separa os trechos é o técnico, respondendo as duas
-- perguntas de comprimento que agora existem.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

create or replace function public.survey_cable_sizing(p_survey_id uuid)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $fn$
declare
  v jsonb; v_amps numeric; v_len numeric; v_volts numeric := 12;
  v_drop numeric := 3; v_engine boolean := false; v_bundle integer := 1;
  v_txt text; v_trechos integer := 0; v_menor numeric;
  v_aviso text; v_ambiguas text;
begin
  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_amps
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'corrente' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

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

  -- Quais respostas que alimentam a conta trazem MAIS DE UM número no texto.
  -- Só conta quando o número não foi gravado como grandeza estruturada: com
  -- `numeric_value` preenchido, alguém já disse qual dos números vale.
  select string_agg(s.rotulo, ' · ') into v_ambiguas
  from (
    select array_to_string(t.affects, '/') || ' ("' || left(a.answer_value, 70)
           || case when length(a.answer_value) > 70 then '…' else '' end || '")' as rotulo
    from public.service_survey_answers a
    join public.service_survey_templates t on t.id = a.template_id
    where a.survey_id = p_survey_id
      and a.skipped_reason is null
      and a.answer_value is not null
      and a.numeric_value is null
      and t.affects && array['corrente','comprimento','tensao','feixe']
      and (select count(*) from regexp_matches(a.answer_value, '\d+[.,]?\d*', 'g')) > 1
  ) s;

  v := public.dc_cable_sizing(v_amps, v_len, v_volts, v_drop, 90,
                              coalesce(v_engine, false), coalesce(v_bundle, 1));

  if coalesce(v_trechos, 0) > 1 then
    v_aviso := 'Foram medidos ' || v_trechos || ' trechos (do menor ' || v_menor
            || ' m ao maior ' || v_len || ' m). A conta usou o MAIS LONGO, que é o '
            || 'único que não subdimensiona nenhum dos dois — mas cada percurso é '
            || 'um circuito e pede o seu próprio cabo. Confira se um cabo só atende.';
  end if;

  if v_ambiguas is not null then
    v_aviso := concat_ws(' ', v_aviso,
      'ATENÇÃO — resposta com mais de um número, e a conta usou o PRIMEIRO: '
      || v_ambiguas || '. Se forem trechos ou circuitos diferentes, responda cada '
      || 'um na sua pergunta; o número que sustenta esta bitola pode ser o errado.');
  end if;

  if v_aviso is not null then
    v := jsonb_set(v, '{aviso}',
           to_jsonb(concat_ws(' ', nullif(v->>'aviso', ''), v_aviso)));
    -- Bitola calculada sobre número ambíguo não é resultado fechado.
    if v_ambiguas is not null then
      v := jsonb_set(v, '{pronto}', 'false'::jsonb);
    end if;
  end if;

  return v || jsonb_build_object(
    'trechos_medidos', coalesce(v_trechos, 0),
    'respostas_ambiguas', v_ambiguas,
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
   trecho medido usa o MAIS LONGO; quando a resposta que alimenta a conta traz
   mais de um número, avisa e derruba `pronto` — bitola calculada sobre número
   ambíguo não é resultado fechado. Dimensionar um cabo POR TRECHO continua
   sendo o destino (NOVO-lev-36).';

commit;
