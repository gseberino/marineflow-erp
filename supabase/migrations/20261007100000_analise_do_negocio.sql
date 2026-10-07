-- Vigia do negócio (07/10/2026, pedido do dono): "o assistente deve sempre avaliar as despesas e
-- receitas, avisar que a margem precisa ser ajustada para que não haja prejuízo, avisar quando uma
-- despesa subiu consideravelmente em relação aos meses anteriores, e identificar que determinado
-- tipo de serviço gera boa parte da receita" (para trabalhar marketing em cima dele).
--
-- Uma função só, de LEITURA, que o assistente (tool analise_do_negocio) e o resumo da manhã
-- (segunda-feira e dia 1) usam. Ela não grava nada.
--
-- O que ela responde, e os cuidados de cada parte (medidos no dado real de 07/10):
--   meses        receita × custo direto × despesas, mês a mês, com "pronto" (checklist_do_mes):
--                setembro tinha R$ 6.239 de receita lançada contra R$ 9.000 de custo — não era
--                prejuízo, era mês sem fechar. Conclusão só sai de mês PRONTO.
--   equilibrio   a receita mínima do mês para não ter prejuízo = despesas fixas médias ÷ margem de
--                contribuição (receita − custo direto). Margem por OS não enxerga aluguel e
--                contador, que são o que vira prejuízo.
--   por_sistema  de onde vem a receita e o lucro das OS (vw_os_profitability, pelo sistema do
--                maior serviço da OS). A mão de obra das diárias só entra quando a diária está
--                ligada à OS — em 07/10 nenhuma das 31 estava, e a função diz quanto ficou de fora.
--   em_alta      categoria de despesa do último mês FECHADO ≥ 30% e ≥ R$ 300 acima da média dos 3
--                meses anteriores (o vigilante diário olha recebedor por recebedor; este olha a
--                categoria no mês).
create or replace function public.analise_do_negocio(p_meses integer default 6)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_meses int := greatest(3, least(coalesce(p_meses, 6), 24));
  v_inicio date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')) - make_interval(months => v_meses))::date;
  v_mes_atual date := date_trunc('month', (now() at time zone 'America/Sao_Paulo'))::date;
  v_alvo numeric := coalesce(nullif((select value from app_settings where key = 'default_profit_margin'), '')::numeric, 30);
  v_meses_json jsonb;
  v_equilibrio jsonb;
  v_sistemas jsonb;
  v_em_alta jsonb;
  v_sem_os jsonb;
  v_ultimo_pronto date;
begin
  -- Pelo app, só admin e financeiro; pelo servidor (assistente no WhatsApp, resumo) não há usuário.
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'Só administrador e financeiro veem a análise do negócio' using errcode = '42501';
  end if;

  -- ── Mês a mês ────────────────────────────────────────────────────────────────────────────
  with meses as (
    select gs::date as mes from generate_series(v_inicio, v_mes_atual, interval '1 month') gs
  ), rec as (
    select date_trunc('month', r.issue_date)::date as mes, sum(r.amount) as receita
    from receivables r
    left join financial_categories c on c.name = r.category and c.type = 'receivable' and c.active
    where r.status <> 'cancelled' and r.issue_date >= v_inicio and coalesce(c.dre_group, 'receita') <> 'nao_operacional'
    group by 1
  ), pag as (
    select date_trunc('month', p.issue_date)::date as mes,
           sum(p.amount) filter (where c.dre_group = 'custo_direto') as custo_direto,
           sum(p.amount) filter (where c.dre_group in ('despesa_operacional', 'financeiro') or c.dre_group is null) as despesas
    from payables p
    left join financial_categories c on c.name = p.expense_category and c.type = 'payable' and c.active
    where p.status <> 'cancelled' and p.issue_date >= v_inicio and coalesce(c.dre_group, '') <> 'nao_operacional'
    group by 1
  )
  select jsonb_agg(jsonb_build_object(
           'mes', to_char(m.mes, 'YYYY-MM'),
           'receita', round(coalesce(rec.receita, 0), 2),
           'custo_direto', round(coalesce(pag.custo_direto, 0), 2),
           'despesas', round(coalesce(pag.despesas, 0), 2),
           'resultado', round(coalesce(rec.receita, 0) - coalesce(pag.custo_direto, 0) - coalesce(pag.despesas, 0), 2),
           'em_andamento', m.mes = v_mes_atual,
           'pronto', m.mes < v_mes_atual and coalesce((public.checklist_do_mes(extract(year from m.mes)::int, extract(month from m.mes)::int)->>'pronto')::boolean, false)
         ) order by m.mes)
    into v_meses_json
  from meses m left join rec on rec.mes = m.mes left join pag on pag.mes = m.mes;

  -- ── Ponto de equilíbrio (só meses prontos; sem 2 prontos, os encerrados, com aviso) ─────
  with base as (
    select (x->>'receita')::numeric as receita, (x->>'custo_direto')::numeric as custo, (x->>'despesas')::numeric as despesas,
           (x->>'pronto')::boolean as pronto
    from jsonb_array_elements(v_meses_json) x
    where not (x->>'em_andamento')::boolean
  ), usados as (
    select * from base where pronto
    union all
    select * from base where (select count(*) from base where pronto) < 2
  ), soma as (
    select count(*) as n, sum(receita) as receita, sum(custo) as custo, sum(despesas) as despesas,
           bool_and(pronto) as so_prontos
    from usados
  )
  select jsonb_build_object(
           'meses_usados', n,
           'so_meses_prontos', coalesce(so_prontos, false),
           'margem_de_contribuicao_pct', case when receita > 0 then round(100 * (receita - custo) / receita, 1) end,
           'despesas_fixas_por_mes', case when n > 0 then round(despesas / n, 2) end,
           'receita_media_por_mes', case when n > 0 then round(receita / n, 2) end,
           'receita_minima_por_mes', case when receita > custo and n > 0 then round((despesas / n) / ((receita - custo) / receita), 2) end
         )
    into v_equilibrio
  from soma;

  -- ── Receita e lucro por sistema (OS concluídas no período) ───────────────────────────────
  with sist as (
    select distinct on (sos.service_order_id) sos.service_order_id,
           coalesce(nullif(sos.service_system, ''), nullif(s.service_system, ''), 'sem_sistema') as sistema
    from service_order_services sos left join services s on s.id = sos.service_id
    order by sos.service_order_id, sos.line_total desc nulls last
  ), base as (
    select coalesce(si.sistema, 'sem_sistema') as sistema, p.revenue, p.net_profit, p.parts_cost, p.labor_cost_real
    from vw_os_profitability p left join sist si on si.service_order_id = p.os_id
    where p.status in ('completed', 'invoiced') and coalesce(p.finished_at, p.created_at) >= v_inicio
  ), ag as (
    select sistema, count(*) as os, sum(revenue) as receita, sum(net_profit) as lucro
    from base group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'sistema', sistema, 'os', os, 'receita', round(receita, 2), 'lucro', round(lucro, 2),
           'margem_pct', case when receita > 0 then round(100 * lucro / receita, 1) end,
           'pct_da_receita', case when (select sum(receita) from ag) > 0 then round(100 * receita / (select sum(receita) from ag), 1) end
         ) order by receita desc), '[]'::jsonb)
    into v_sistemas
  from ag;

  -- ── Despesa por categoria em alta (último mês PRONTO; sem nenhum pronto, o último encerrado) ──
  select coalesce(
           max(to_date(x->>'mes', 'YYYY-MM')) filter (where (x->>'pronto')::boolean),
           max(to_date(x->>'mes', 'YYYY-MM')) filter (where not (x->>'em_andamento')::boolean))
    into v_ultimo_pronto
  from jsonb_array_elements(v_meses_json) x;

  with por_cat as (
    select p.expense_category as categoria, date_trunc('month', p.issue_date)::date as mes, sum(p.amount) as total
    from payables p
    left join financial_categories c on c.name = p.expense_category and c.type = 'payable' and c.active
    where p.status <> 'cancelled' and coalesce(c.dre_group, '') <> 'nao_operacional'
      and p.issue_date >= (v_ultimo_pronto - interval '3 months') and p.issue_date < (v_ultimo_pronto + interval '1 month')
      and p.expense_category is not null
    group by 1, 2
  ), comp as (
    select categoria,
           coalesce(sum(total) filter (where mes = v_ultimo_pronto), 0) as no_mes,
           coalesce(sum(total) filter (where mes < v_ultimo_pronto), 0) / 3.0 as media_3
    from por_cat group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'categoria', categoria, 'mes', to_char(v_ultimo_pronto, 'YYYY-MM'),
           'no_mes', round(no_mes, 2), 'media_3_meses_antes', round(media_3, 2),
           'alta_pct', case when media_3 > 0 then round(100 * (no_mes - media_3) / media_3, 0) end
         ) order by no_mes - media_3 desc), '[]'::jsonb)
    into v_em_alta
  from comp
  where v_ultimo_pronto is not null and no_mes - media_3 >= 300 and (media_3 = 0 or no_mes >= media_3 * 1.3);

  -- ── Mão de obra que o lucro por OS não vê ────────────────────────────────────────────────
  select jsonb_build_object('diarias', count(*), 'valor', round(coalesce(sum(w.valor_dia), 0), 2))
    into v_sem_os
  from work_shifts w
  where w.data >= v_inicio and coalesce(w.status, '') <> 'cancelado'
    and not exists (select 1 from work_shift_os x where x.shift_id = w.id);

  return jsonb_build_object(
    'periodo', jsonb_build_object('de', v_inicio, 'ate', (now() at time zone 'America/Sao_Paulo')::date),
    'margem_alvo_pct', v_alvo,
    'meses', coalesce(v_meses_json, '[]'::jsonb),
    'equilibrio', v_equilibrio,
    'por_sistema', v_sistemas,
    'em_alta', v_em_alta,
    'mao_de_obra_sem_os', v_sem_os
  );
end;
$$;

revoke all on function public.analise_do_negocio(integer) from public;
revoke all on function public.analise_do_negocio(integer) from anon;
grant execute on function public.analise_do_negocio(integer) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007100000', 'analise_do_negocio');
