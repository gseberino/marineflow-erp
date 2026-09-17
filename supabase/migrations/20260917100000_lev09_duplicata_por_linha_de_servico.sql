-- D10 (decisão do dono, 17/09/2026) — NOVO-lev-09: a unidade de duplicata do
-- apply_survey_materials passa a ser (linha de serviço, produto), e regras selecionadas
-- na mesma chamada que apontam para o mesmo produto somam a quantidade em vez de
-- entrarem em dobro. Corpo da função copiado da produção em 17/09 e alterado só nos
-- dois trechos comentados como "lev-09".

CREATE OR REPLACE FUNCTION public.apply_survey_materials(p_survey_id uuid, p_rule_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_os uuid; v_linha uuid; v_service uuid; v_criadas integer := 0;
  v_selecionadas integer := 0; v_sem_numero integer := 0;
  v_qtd_invalida integer := 0; v_ja_lancadas integer := 0;
  v_motivos text[] := '{}';
  v_mensagem text;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select s.service_order_id, s.service_id into v_os, v_service
  from public.service_surveys s where s.id = p_survey_id;

  if v_os is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este levantamento não está ligado a um orçamento ou OS.');
  end if;

  -- A linha do serviço, quando existir: é por ela que a folha impressa agrupa
  -- o material por etapa.
  select id into v_linha from public.service_order_services
  where service_order_id = v_os and service_id = v_service
  order by created_at limit 1;

  -- O que vai ficar de fora, e por quê — contado antes do insert, no mesmo
  -- instantâneo que ele vai ler. Os três filtros são uma partição das linhas
  -- selecionadas: tudo que não entra cai em exatamente um deles.
  select count(*),
         count(*) filter (where m.quantity is null),
         count(*) filter (where m.quantity is not null and m.quantity <= 0),
         count(*) filter (where m.quantity > 0 and exists (
           select 1 from public.service_order_parts x
           where x.service_order_id = v_os
             and x.service_order_service_id is not distinct from v_linha
             and x.product_id = m.product_id
             and x.source = 'survey'))
    into v_selecionadas, v_sem_numero, v_qtd_invalida, v_ja_lancadas
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids);

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale,
     source, notes)
  select v_os, v_linha, g.product_id, g.quantity,
         g.unit_cost, g.unit_sale,
         g.unit_cost * g.quantity, g.unit_sale * g.quantity,
         'survey',
         g.notes
  from (
    -- Uma linha por PRODUTO: duas regras selecionadas juntas apontando para o mesmo
    -- produto (cabo banco→inversor e inversor→quadro) somam a quantidade, em vez de
    -- passarem as duas pela trava — que lê o instantâneo de antes do insert (lev-09).
    select m.product_id,
           sum(m.quantity)  as quantity,
           max(m.unit_cost) as unit_cost,
           max(m.unit_sale) as unit_sale,
           left(string_agg('Do levantamento: ' || left(m.question, 60) || ' → ' || left(m.answer, 40),
                           ' | ' order by m.question), 500) as notes
    from public.survey_suggested_materials(p_survey_id) m
    where m.rule_id = any(p_rule_ids)
      and m.quantity is not null
      and m.quantity > 0
      -- Não lança duas vezes o mesmo produto NA MESMA LINHA DE SERVIÇO vindo do
      -- levantamento. Dois serviços da mesma OS que precisem do mesmo produto (dois
      -- bancos de bateria) recebem material cada um — antes o segundo ficava sem.
      and not exists (
        select 1 from public.service_order_parts x
        where x.service_order_id = v_os
          and x.service_order_service_id is not distinct from v_linha
          and x.product_id = m.product_id
          and x.source = 'survey')
    group by m.product_id
  ) g;

  get diagnostics v_criadas = row_count;

  if v_sem_numero > 0 then
    v_motivos := v_motivos || (v_sem_numero || ' sem número na resposta — corrija a resposta do levantamento e lance de novo');
  end if;
  if v_qtd_invalida > 0 then
    v_motivos := v_motivos || (v_qtd_invalida || ' com quantidade zero ou negativa');
  end if;
  if v_ja_lancadas > 0 then
    v_motivos := v_motivos || (v_ja_lancadas || ' já estava(m) no orçamento');
  end if;

  if v_criadas > 0 then
    v_mensagem := v_criadas || ' item(ns) lançado(s) a partir do levantamento'
      || case when cardinality(v_motivos) > 0
              then '. Ficaram de fora: ' || array_to_string(v_motivos, '; ') || '.'
              else '.' end;
  elsif v_selecionadas = 0 then
    v_mensagem := 'Nenhuma sugestão selecionada para lançar.';
  else
    v_mensagem := 'Nada foi lançado: ' || array_to_string(v_motivos, '; ') || '.';
  end if;

  return jsonb_build_object('ok', true, 'linhas_criadas', v_criadas,
    'descartadas', jsonb_build_object(
      'sem_numero', v_sem_numero,
      'quantidade_invalida', v_qtd_invalida,
      'ja_lancadas', v_ja_lancadas),
    'mensagem', v_mensagem);
end;
$function$
;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260917100000', 'lev09_duplicata_por_linha_de_servico')
on conflict do nothing;
