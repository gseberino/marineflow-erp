-- ═══════════════════════════════════════════════════════════════════════════
-- A composição passa a devolver a unidade e a faixa
--
-- Sem isto os campos novos existem na tabela e não chegam à tela nem à folha:
-- a unidade continuaria só na cabeça de quem cadastrou, e o aviso de "confira
-- a vírgula" não teria contra o que comparar.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.compose_survey_for_service(
  p_service_id uuid,
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
  origem text,
  expected_unit text,
  min_expected numeric,
  max_expected numeric)
language plpgsql stable security invoker set search_path = public
as $fn$
declare v_verb text; v_sys text; v_proprias integer;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select service_verb, service_system into v_verb, v_sys
  from public.services where services.id = p_service_id;

  select count(*) into v_proprias
  from public.service_survey_templates t
  where t.service_id = p_service_id and t.active;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.service_id is not null then 'serviço'
              when t.applies_to_system is not null then 'sistema'
              else 'verbo' end,
         t.expected_unit, t.min_expected, t.max_expected
  from public.service_survey_templates t
  where t.active
    and (p_mode <> 'remoto' or t.ask_remotely)
    and (
      (v_proprias > 0 and t.service_id = p_service_id)
      or (v_proprias = 0 and (
            (t.applies_to_system is not null and t.applies_to_system = v_sys)
         or (t.applies_to_verb   is not null and t.applies_to_verb   = v_verb)))
    )
  order by case t.price_impact when 'alto' then 0 when 'medio' then 1 else 2 end,
           t.seq
  limit 9;  -- teto do P16: mais que nove perguntas ninguém responde em campo
end;
$fn$;

revoke all on function public.compose_survey_for_service(uuid, text) from public, anon;
grant execute on function public.compose_survey_for_service(uuid, text) to authenticated;

-- Mesma coisa para a composição por eixo, usada pela análise da descrição.
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
  origem text,
  expected_unit text,
  min_expected numeric,
  max_expected numeric)
language plpgsql stable security invoker set search_path = public
as $fn$
begin
  if p_system is null and p_verb is null then
    return;
  end if;

  return query
  select t.id, t.seq, t.question, t.help_text, t.answer_type, t.options,
         t.price_impact, t.ask_remotely,
         case when t.applies_to_system is not null then 'sistema' else 'verbo' end,
         t.expected_unit, t.min_expected, t.max_expected
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

-- ───────────────────────────────────────────────────────────────────────────
-- O dimensionador passa a ler o NÚMERO gravado, e não a garimpar na frase
--
-- `numeric_value` é preenchido pela tela quando a pergunta é de grandeza. Onde
-- ele existir, é ele que vale; onde não existir — respostas antigas, ou texto
-- lançado pela folha de campo — continua valendo o parse do texto, para o
-- histórico não parar de funcionar.
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
  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_amps
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'corrente' = any(t.affects)
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_len
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'comprimento' = any(t.affects)
    and (a.numeric_value is not null or a.answer_value is not null)
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
  if v_txt is not null and v_txt ilike '%não crítico%' then v_drop := 10; end if;

  select lower(trim(a.answer_value)) in ('sim','s','true') into v_engine
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'casa_maquinas' = any(t.affects)
    and a.answer_value is not null
  order by a.answered_at desc nulls last limit 1;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value), 1)::integer
    into v_bundle
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'feixe' = any(t.affects)
    and (a.numeric_value is not null or a.answer_value is not null)
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
