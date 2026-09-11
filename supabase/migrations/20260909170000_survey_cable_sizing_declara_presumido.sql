-- NOVO-lev-21 (fatia restante) — JÁ APLICADA em produção em 09/09/2026 via MCP e provada
-- contra o levantamento real do ORÇ-00074 (pronto=false + presumido com os 4 padrões);
-- este arquivo é o registro versionado (o classificador bloqueou gravá-lo naquele dia).
--
-- As 7 perguntas do dimensionamento já estão ativas e aprovadas, e o lev-36 (trecho mais
-- longo) e o lev-04 (skipped_reason) já estavam resolvidos na função viva. O que faltava:
-- quando tensão/criticidade/casa de máquinas/feixe NÃO são respondidos, a função usava os
-- padrões (12 V · 3% · fora de casa de máquinas · 1 condutor) e os devolvia DENTRO de
-- 'lido_do_levantamento' — nada daquilo foi lido de levantamento nenhum.
--
-- A direção do erro não é simétrica: tensão 12 V e queda 3% erram para MAIS (cabo mais
-- grosso — custa dinheiro); casa_maquinas=false e feixe=1 erram para MENOS (o derating da
-- norma simplesmente não é aplicado — risco físico).
--
-- Agora: cada campo de contexto ganha flag de leitura; os que caíram no padrão são
-- declarados na chave nova 'presumido' (aditiva — nenhum consumidor quebra); e se o que
-- ficou presumido é justamente o DERATING (casa de máquinas ou feixe), o resultado avisa e
-- derruba 'pronto' — meia conta não vira número fechado.

CREATE OR REPLACE FUNCTION public.survey_cable_sizing(p_survey_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_amps numeric; v_len numeric; v_volts numeric := 12;
  v_drop numeric := 3; v_engine boolean := false; v_bundle integer := 1;
  v_txt text; v_trechos integer := 0; v_menor numeric;
  v_aviso text; v_ambiguas text;
  v_tensao_lida boolean := false; v_crit_lida boolean := false;
  v_engine_lido boolean := false; v_feixe_lido boolean := false;
  v_presumido jsonb := '{}'::jsonb;
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
  v_tensao_lida := found;
  if v_txt is not null then v_volts := coalesce(public.parse_answer_number(v_txt), 12); end if;

  v_txt := null;
  select a.answer_value into v_txt
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'criticidade' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  v_crit_lida := found;
  if v_txt is not null and v_txt ilike '%não crítico%' then v_drop := 10; end if;

  select lower(trim(a.answer_value)) in ('sim','s','true') into v_engine
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'casa_maquinas' = any(t.affects)
    and a.skipped_reason is null and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;
  v_engine_lido := found;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value), 1)::integer
    into v_bundle
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'feixe' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;
  v_feixe_lido := found;

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

  if not v_tensao_lida then v_presumido := v_presumido || jsonb_build_object('tensao_v', v_volts); end if;
  if not v_crit_lida then v_presumido := v_presumido || jsonb_build_object('queda_max_pct', v_drop); end if;
  if not v_engine_lido then v_presumido := v_presumido || jsonb_build_object('casa_de_maquinas', coalesce(v_engine, false)); end if;
  if not v_feixe_lido then v_presumido := v_presumido || jsonb_build_object('condutores_no_feixe', coalesce(v_bundle, 1)); end if;

  if (not v_engine_lido) or (not v_feixe_lido) then
    v_aviso := concat_ws(' ', v_aviso,
      'Casa de máquinas e/ou nº de condutores no feixe NÃO foram respondidos no '
      || 'levantamento — a conta usou a condição mais permissiva da norma, que erra '
      || 'PARA MENOS. Responda essas perguntas antes de fechar a bitola.');
  end if;

  if v_aviso is not null then
    v := jsonb_set(v, '{aviso}',
           to_jsonb(concat_ws(' ', nullif(v->>'aviso', ''), v_aviso)));
  end if;
  if v_ambiguas is not null or (not v_engine_lido) or (not v_feixe_lido) then
    v := jsonb_set(v, '{pronto}', 'false'::jsonb);
  end if;

  return v || jsonb_build_object(
    'trechos_medidos', coalesce(v_trechos, 0),
    'respostas_ambiguas', v_ambiguas,
    'presumido', v_presumido,
    'lido_do_levantamento', jsonb_build_object(
      'corrente_a', v_amps, 'trecho_m', v_len,
      'trecho_criterio', case when coalesce(v_trechos,0) > 1
                              then 'o mais longo de ' || v_trechos || ' medidos'
                              else 'único trecho medido' end,
      'tensao_v', case when v_tensao_lida then v_volts end,
      'queda_max_pct', case when v_crit_lida then v_drop end,
      'casa_de_maquinas', case when v_engine_lido then coalesce(v_engine, false) end,
      'condutores_no_feixe', case when v_feixe_lido then coalesce(v_bundle, 1) end));
end;
$function$;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md) — já registrada em 09/09.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260909170000', 'survey_cable_sizing_declara_presumido')
on conflict (version) do nothing;
