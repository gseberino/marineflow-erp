-- ═══════════════════════════════════════════════════════════════════════════
-- A regra do cabo para de apontar um produto fixo
--
-- Fecha o ciclo aberto em 08/08, quando o dono perguntou se o "Cabo flexível
-- 35 mm²" sugerido no ORÇ-00074 batia com a Blue Sea / ABYC. Não batia — e o
-- motivo não era a tabela, era o desenho: a regra de material escolhia o
-- produto por `condition_type = 'sempre'`, e o dimensionamento, quando passou a
-- existir, calculava a bitola sem que ninguém o consultasse.
--
-- Agora a regra pode dizer "o produto vem do dimensionamento". A conta da
-- QUANTIDADE continua igual — 2 m de cabo por metro medido, +15% de folga, o
-- positivo vai e o negativo volta. O que muda é QUAL cabo.
--
-- ═══ QUANDO NÃO DÁ PARA ESCOLHER ═══
--
-- A linha aparece assim mesmo, com o motivo e SEM quantidade. O painel desabilita
-- a caixa quando não há quantidade, e `apply_survey_materials` já filtra
-- `quantity is not null` — então cabo não resolvido não entra no orçamento por
-- nenhum caminho. Some da lista seria pior: quem confere não saberia que falta
-- um cabo.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

alter table public.survey_material_rules
  add column if not exists product_pick text not null default 'fixo'
    check (product_pick in ('fixo', 'cabo_por_dimensionamento'));

comment on column public.survey_material_rules.product_pick is
  'De onde vem o PRODUTO. "fixo" usa product_id, como sempre.
   "cabo_por_dimensionamento" ignora product_id e pergunta a
   dc_cable_product_for() qual cabo do catálogo atende o circuito deste
   levantamento pelos dois critérios da ABYC. A quantidade continua saindo da
   regra nos dois casos.';

-- ───────────────────────────────────────────────────────────────────────────
-- De passagem, o NOVO-lev-04: resposta PULADA alimentava o dimensionamento
--
-- As seis leituras filtravam `(numeric_value is not null or answer_value is not
-- null)` e NÃO filtravam `skipped_reason`. Uma resposta que alguém retirou —
-- "não consegui ver" — continuava entrando na conta, porque marcar como pulada
-- não apaga o `numeric_value` já gravado.
--
-- Enquanto isso só afetava um número na tela, era achado registrado. A partir
-- desta migration esse número escolhe o CABO, e passa a ser caminho crítico.
-- `survey_suggested_materials` sempre filtrou; as duas ficam iguais agora.
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
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

  select coalesce(a.numeric_value, public.parse_answer_number(a.answer_value))
    into v_len
  from public.service_survey_answers a
  join public.service_survey_templates t on t.id = a.template_id
  where a.survey_id = p_survey_id and 'comprimento' = any(t.affects)
    and a.skipped_reason is null
    and (a.numeric_value is not null or a.answer_value is not null)
  order by a.answered_at desc nulls last limit 1;

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

  return v || jsonb_build_object('lido_do_levantamento', jsonb_build_object(
    'corrente_a', v_amps, 'trecho_m', v_len, 'tensao_v', v_volts,
    'queda_max_pct', v_drop, 'casa_de_maquinas', coalesce(v_engine, false),
    'condutores_no_feixe', coalesce(v_bundle, 1)));
end;
$fn$;

revoke all on function public.survey_cable_sizing(uuid) from public, anon;
grant execute on function public.survey_cable_sizing(uuid) to authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- A sugestão de material passa a consultar o dimensionamento
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.survey_suggested_materials(p_survey_id uuid)
returns table (
  rule_id uuid, product_id uuid, product_name text, unit text, question text,
  answer text, quantity numeric, unit_sale numeric, unit_cost numeric,
  line_total numeric, rationale text, alerta text)
language sql stable security invoker set search_path = public
as $fn$
  with sizing as (
    select public.survey_cable_sizing(p_survey_id) as s
  ),
  escolha as (
    select public.dc_cable_product_for(
             (s->'lido_do_levantamento'->>'corrente_a')::numeric,
             (s->'lido_do_levantamento'->>'trecho_m')::numeric,
             (s->'lido_do_levantamento'->>'tensao_v')::numeric,
             (s->'lido_do_levantamento'->>'queda_max_pct')::numeric,
             (s->'lido_do_levantamento'->>'casa_de_maquinas')::boolean,
             (s->'lido_do_levantamento'->>'condutores_no_feixe')::integer) as e
    from sizing
  ),
  respondidas as (
    select a.template_id, a.answer_value,
           public.parse_answer_number(a.answer_value) as numero
    from public.service_survey_answers a
    where a.survey_id = p_survey_id
      and a.answer_value is not null
      and a.skipped_reason is null
  ),
  casadas as (
    select r.*, q.answer_value, q.numero, t.question as pergunta
    from respondidas q
    join public.survey_material_rules r on r.template_id = q.template_id and r.active
    join public.service_survey_templates t on t.id = r.template_id
    where case r.condition_type
      when 'sempre' then true
      when 'igual'  then lower(trim(q.answer_value)) = lower(trim(r.match_value))
      when 'contem' then q.answer_value ilike '%' || r.match_value || '%'
      when 'sim'    then lower(trim(q.answer_value)) in ('sim', 's', 'true')
      when 'nao'    then lower(trim(q.answer_value)) in ('não', 'nao', 'n', 'false')
      when 'faixa'  then q.numero is not null
                        and (r.min_value is null or q.numero >= r.min_value)
                        and (r.max_value is null or q.numero < r.max_value)
      else false
    end
  ),
  quantificadas as (
    select c.*,
      case c.qty_mode
        when 'fixa' then c.qty_fixed
        else case when c.numero is null then null else c.numero * c.qty_factor end
      end * (1 + c.qty_slack_pct / 100.0) as bruta
    from casadas c
  ),
  -- Qual produto vale para esta linha, e por que ele pode não existir.
  alvo as (
    select q.*,
      case when q.product_pick = 'cabo_por_dimensionamento'
           then ((select e->'produto'->>'id' from escolha))::uuid
           else q.product_id end as pid,
      case when q.product_pick = 'cabo_por_dimensionamento'
           then (select e->>'motivo' from escolha) end as motivo_cabo
    from quantificadas q
  ),
  contas as (
    select a.*,
      case when a.product_pick = 'cabo_por_dimensionamento' and a.pid is null then null
           when a.qty_round = 'cima' then ceil(a.bruta)
           when a.qty_round = 'meio' then ceil(a.bruta * 2) / 2
           else round(a.bruta, 2) end as qtd
    from alvo a
  )
  select
    c.id as rule_id,
    coalesce(c.pid, c.product_id) as product_id,
    case when c.product_pick = 'cabo_por_dimensionamento' and c.pid is null
         then 'Cabo — não foi possível escolher'
         else p.name end as product_name,
    p.unit,
    c.pergunta,
    c.answer_value,
    c.qtd as quantity,
    coalesce(p.sale_price, 0) as unit_sale,
    coalesce(p.cost_price, 0) as unit_cost,
    case when c.qtd is null then null
         else round(coalesce(p.sale_price, 0) * c.qtd, 2) end as line_total,
    c.rationale,
    nullif(concat_ws(' · ',
      c.motivo_cabo,
      case when c.product_pick = 'cabo_por_dimensionamento' and c.pid is not null
        then 'bitola escolhida pelo dimensionamento (ABYC E-11), não pela regra' end,
      case when c.bruta is null and c.pid is not null
        then 'a resposta não tem número — confira a quantidade' end,
      case when c.qty_mode <> 'fixa'
             and (select count(*) from regexp_matches(c.answer_value, '\d+[.,]?\d*', 'g')) > 1
        then 'a resposta tem mais de um número: usei o primeiro ('
             || trim(to_char(c.numero, 'FM999999.99')) || ') — confira se falta somar os outros' end,
      case when c.qty_mode = 'proporcional' and p.id is not null
             and lower(coalesce(p.unit, '')) not in ('m', 'mt', 'metro', 'metros')
        then 'a regra calcula metros mas o produto é vendido em "' || coalesce(p.unit, '—') || '"' end,
      case when p.id is not null and coalesce(p.cost_price, 0) = 0
        then 'produto sem custo cadastrado: a margem desta linha não é calculável' end,
      case when p.id is not null and coalesce(p.sale_price, 0) = 0
        then 'produto sem preço de venda' end
    ), '') as alerta
  from contas c
  left join public.products p on p.id = coalesce(c.pid, c.product_id)
  order by 3;
$fn$;

revoke all on function public.survey_suggested_materials(uuid) from public, anon;
grant execute on function public.survey_suggested_materials(uuid) to authenticated;

comment on function public.survey_suggested_materials(uuid) is
  'O material que as respostas deste levantamento implicam. Só calcula — não
   grava. A regra em modo "cabo_por_dimensionamento" tem o produto escolhido por
   dc_cable_product_for(); quando nenhum cabo atende, a linha vem sem quantidade
   e com o motivo no alerta, e por isso não pode ser lançada.';

-- A regra que existe hoje passa a escolher o cabo pelo dimensionamento. O
-- product_id fica como estava: serve de referência do que a regra apontava
-- antes, e não é mais usado enquanto o modo for este.
update public.survey_material_rules
   set product_pick = 'cabo_por_dimensionamento',
       rationale = 'O circuito é de ida e volta: o positivo vai e o negativo volta, '
                || 'por isso 2 m de cabo por metro medido, mais 15% de folga (cabo se '
                || 'corta com sobra). A BITOLA sai do dimensionamento pelos dois '
                || 'critérios da ABYC E-11, não desta regra.'
 where product_pick = 'fixo'
   and qty_mode = 'proporcional'
   and product_id in (select id from public.products where conductor_mm2 is not null);

commit;
