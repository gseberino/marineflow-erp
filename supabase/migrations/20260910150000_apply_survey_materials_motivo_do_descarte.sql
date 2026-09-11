-- NOVO-lev-08 · apply_survey_materials: o `insert ... select` descarta sugestão por três
-- motivos diferentes — quantidade nula (a resposta não tinha número), quantidade <= 0 e
-- produto já lançado por este mesmo caminho — e os três caíam no mesmo `v_criadas = 0`,
-- respondido como "esses materiais já estavam no orçamento". Para quem conferiu uma
-- sugestão marcada "a resposta não tem número" e mandou lançar, a frase manda parar de
-- procurar: o material não está lá e não vai estar, e o que precisava era corrigir a
-- resposta do levantamento.
--
-- Agora a função conta o descarte por motivo ANTES de inserir e diz qual foi. Os números
-- também vão no JSON ('descartadas'), para a tela poder mostrar por linha se quiser.
-- A regra de duplicata (por ordem, source = 'survey') continua a mesma — a unidade de
-- duplicata (ordem × linha de serviço) é decisão de negócio em aberto (NOVO-lev-09).

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
             and x.product_id = m.product_id
             and x.source = 'survey'))
    into v_selecionadas, v_sem_numero, v_qtd_invalida, v_ja_lancadas
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids);

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale,
     source, notes)
  select v_os, v_linha, m.product_id, m.quantity,
         m.unit_cost, m.unit_sale,
         m.unit_cost * m.quantity, m.unit_sale * m.quantity,
         'survey',
         'Do levantamento: ' || left(m.question, 60) || ' → ' || left(m.answer, 40)
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids)
    and m.quantity is not null
    and m.quantity > 0
    -- Não lança duas vezes o mesmo produto vindo do mesmo levantamento.
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = v_os
        and x.product_id = m.product_id
        and x.source = 'survey');

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
$function$;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260910150000', 'apply_survey_materials_motivo_do_descarte')
on conflict (version) do nothing;
