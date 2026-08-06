-- ═══════════════════════════════════════════════════════════════════════════
-- O aviso de bitola vai para a linha do material
--
-- No ORÇ-00074 a regra sugeria "Cabo flexível 35 mm²" porque foi o produto que
-- eu fixei nela — a regra calcula comprimento, não bitola. Com a corrente que
-- o levantamento já registrava (250 A, 2,5 m, 12 V), a queda de tensão de 3%
-- exige 62 mm². Quase o dobro.
--
-- O dono só descobriu porque desconfiou e perguntou. Ninguém deveria precisar
-- desconfiar: o aviso tem que estar na linha, ao lado do botão que lança.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.survey_suggested_materials(p_survey_id uuid)
returns table (
  rule_id uuid,
  product_id uuid,
  product_name text,
  unit text,
  question text,
  answer text,
  quantity numeric,
  unit_sale numeric,
  unit_cost numeric,
  line_total numeric,
  rationale text,
  alerta text)
language sql stable security invoker set search_path = public
as $fn$
  with dim as (
    -- Uma vez só: o dimensionamento vale para o levantamento inteiro.
    select public.survey_cable_sizing(p_survey_id) as d
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
  final as (
    select q.*, p.id as pid, p.name as pname, p.unit as punit,
           coalesce(p.sale_price, 0) as venda, coalesce(p.cost_price, 0) as custo,
           case q.qty_round
             when 'cima' then ceil(q.bruta)
             when 'meio' then ceil(q.bruta * 2) / 2
             else round(q.bruta, 2)
           end as qtd,
           -- Bitola anunciada no nome do produto. Só para cabo: em outros
           -- itens um "mm" no nome é medida de outra coisa.
           case when p.name ~* 'cabo'
             then public.parse_answer_number(
                    substring(replace(p.name, ',', '.') from '(\d+\.?\d*)\s*mm'))
           end as mm2_do_produto
    from quantificadas q
    join public.products p on p.id = q.product_id
  )
  select
    f.id, f.pid, f.pname, f.punit, f.pergunta, f.answer_value, f.qtd,
    f.venda, f.custo, round(f.venda * coalesce(f.qtd, 0), 2), f.rationale,
    nullif(concat_ws(' · ',
      -- O aviso de bitola vem PRIMEIRO: é o único que, ignorado, esquenta
      -- cabo. Os outros custam dinheiro; este custa segurança.
      case when f.mm2_do_produto is not null
            and (dim.d->>'mm2_minimo')::numeric > f.mm2_do_produto
        then 'BITOLA ABAIXO DO CALCULADO: este cabo tem ' || f.mm2_do_produto
             || ' mm² e o circuito pede ' || (dim.d->>'mm2_minimo')
             || ' mm² (' || coalesce(dim.d->>'criterio_que_manda', 'queda de tensão')
             || '). Troque o produto da regra.' end,
      case when f.mm2_do_produto is not null and (dim.d->>'pronto')::boolean is false
             and (dim.d->>'ampacidade_cadastrada')::boolean is false
        then 'a ampacidade não foi conferida — só a queda de tensão entrou na conta' end,
      case when f.bruta is null
        then 'a resposta não tem número — confira a quantidade' end,
      case when f.qty_mode <> 'fixa'
             and (select count(*) from regexp_matches(f.answer_value, '\d+[.,]?\d*', 'g')) > 1
        then 'a resposta tem mais de um número: usei o primeiro ('
             || trim(to_char(f.numero, 'FM999999.99')) || ') — confira se falta somar os outros' end,
      case when f.qty_mode = 'proporcional'
             and lower(coalesce(f.punit, '')) not in ('m', 'mt', 'metro', 'metros')
        then 'a regra calcula metros mas o produto é vendido em "' || coalesce(f.punit, '—') || '"' end,
      case when f.custo = 0
        then 'produto sem custo cadastrado: a margem desta linha não é calculável' end,
      case when f.venda = 0 then 'produto sem preço de venda' end
    ), '')
  from final f cross join dim
  order by f.pname;
$fn$;

revoke all on function public.survey_suggested_materials(uuid) from public, anon;
grant execute on function public.survey_suggested_materials(uuid) to authenticated;

comment on function public.survey_suggested_materials(uuid) is
  'O material que as respostas implicam. Só calcula — não grava. O primeiro
   alerta de cada linha é o de bitola: ignorar os outros custa dinheiro,
   ignorar esse esquenta cabo.';
