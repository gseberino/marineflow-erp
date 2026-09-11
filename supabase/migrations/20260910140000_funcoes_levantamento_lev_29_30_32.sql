-- Três achados da varredura do Levantamento (audit/novos-achados.md) que vivem em função:
--
-- NOVO-lev-29 · related_materials: `distinct on (sugerido)` obriga a ordenar por id primeiro,
--   então a lista saía em ORDEM DE UUID e sem teto. Agora o melhor vínculo por produto é
--   escolhido numa CTE e a lista final vai do vínculo mais forte ao mais fraco, limitada a 8.
--
-- NOVO-lev-30 · estimate_from_cases: o `limit 5` estava DEPOIS do `jsonb_agg` — limitava a
--   linha agregada (uma só), não os casos. A folha do técnico receberia TODAS as execuções.
--   Agora o limite entra na subconsulta, antes de agregar.
--
-- NOVO-lev-32 · should_survey_service: `value::numeric` sem proteção — um '3.000' ou
--   'R$ 3000' em app_settings.survey_valor_limiar derrubava o painel de TODOS os serviços
--   (e app_settings era gravável por qualquer autenticado até 09/09). Agora o valor passa por
--   parse_valor_ptbr, que entende pt-BR ('1.500' = mil e quinhentos, decisão do dono de
--   12/08; '1.234,56'; 'R$ 3.000') e devolve NULL em vez de exceção — cai no padrão 3000.

-- ── parse_valor_ptbr: número pt-BR de texto livre, sem exceção ───────────────
CREATE OR REPLACE FUNCTION public.parse_valor_ptbr(p_texto text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  v := regexp_replace(coalesce(p_texto, ''), '[^0-9.,]', '', 'g');
  if v = '' then return null; end if;
  if position(',' in v) > 0 then
    -- vírgula presente: ponto é milhar, vírgula é decimal
    v := replace(replace(v, '.', ''), ',', '.');
  elsif v ~ '^\d{1,3}(\.\d{3})+$' then
    -- só pontos em grupos de 3: milhar pt-BR ('1.500' = 1500)
    v := replace(v, '.', '');
  end if;
  if v !~ '^\d+(\.\d+)?$' then return null; end if;
  return v::numeric;
exception when others then
  return null;
end;
$function$;

COMMENT ON FUNCTION public.parse_valor_ptbr(text) IS
  'Número pt-BR a partir de texto livre (R$, milhar com ponto, decimal com vírgula). NULL se não der — nunca exceção.';

REVOKE ALL ON FUNCTION public.parse_valor_ptbr(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.parse_valor_ptbr(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.parse_valor_ptbr(text) TO authenticated, service_role;

-- ── lev-29 · related_materials ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.related_materials(p_service_order_id uuid, p_min_juntos integer DEFAULT 3)
 RETURNS TABLE(product_id uuid, product_name text, unit text, sale_price numeric, por_causa_de text, juntos integer, de_total integer, pct integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with na_os as (
    select distinct sop.product_id
    from public.service_order_parts sop
    where sop.service_order_id = p_service_order_id
  ),
  -- Onde mais cada item desta ordem já apareceu. A ordem ATUAL fica de fora
  -- das duas contagens: o que interessa é "nas outras vezes que você usou
  -- isto", e incluir a de agora inflaria o denominador sem informar nada.
  ordens_com as (
    select n.product_id as base, sop.service_order_id
    from na_os n
    join public.service_order_parts sop on sop.product_id = n.product_id
    where sop.service_order_id <> p_service_order_id
  ),
  total_base as (
    select base, count(distinct service_order_id)::integer as de_total
    from ordens_com group by base
  ),
  companheiros as (
    select o.base, x.product_id as sugerido,
           count(distinct x.service_order_id)::integer as juntos
    from ordens_com o
    join public.service_order_parts x
      on x.service_order_id = o.service_order_id and x.product_id <> o.base
    where not exists (select 1 from na_os n where n.product_id = x.product_id)
    group by o.base, x.product_id
  ),
  -- distinct on (sugerido): um produto pode ser puxado por vários itens da
  -- ordem. Mostrar o mesmo material três vezes, uma por origem, transformaria
  -- a lista num quebra-cabeça — fica o vínculo mais forte.
  melhor_vinculo as (
    select distinct on (c.sugerido)
      p.id as product_id, p.name as product_name, p.unit,
      coalesce(p.sale_price, 0) as sale_price,
      base.name as por_causa_de,
      c.juntos, t.de_total,
      round(100.0 * c.juntos / nullif(t.de_total, 0))::integer as pct
    from companheiros c
    join total_base t on t.base = c.base
    join public.products p on p.id = c.sugerido
    join public.products base on base.id = c.base
    where c.juntos >= p_min_juntos
      and p.active
    order by c.sugerido, pct desc, c.juntos desc
  )
  -- NOVO-lev-29: o distinct on obriga a ordenar por id; a ordem que a tela precisa
  -- (mais forte primeiro) e o teto (8) entram aqui, por fora.
  select mv.product_id, mv.product_name, mv.unit, mv.sale_price, mv.por_causa_de,
         mv.juntos, mv.de_total, mv.pct
  from melhor_vinculo mv
  order by mv.pct desc, mv.juntos desc, mv.product_name
  limit 8;
$function$;

-- ── lev-30 · estimate_from_cases ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.estimate_from_cases(p_service_id uuid, p_min_casos integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n integer; v_p50 numeric; v_p80 numeric; v_casos jsonb;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select count(*),
         percentile_cont(0.5) within group (order by actual_minutes),
         percentile_cont(0.8) within group (order by actual_minutes)
    into v_n, v_p50, v_p80
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_n < p_min_casos then
    return jsonb_build_object('tem_base', false, 'casos', v_n,
      'mensagem', 'Sem base suficiente: ' || v_n || ' execução(ões) registrada(s), mínimo ' || p_min_casos ||
                  '. Use o tempo padrão do roteiro e trate a estimativa como provisória.');
  end if;

  -- NOVO-lev-30: o limit fica na SUBCONSULTA — depois do jsonb_agg ele limitava a linha
  -- agregada (uma só), e a folha recebia todas as execuções numa linha.
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', x.os, 'minutos', x.minutos, 'quando', x.quando)
         order by x.quando desc), '[]'::jsonb) into v_casos
  from (
    select so.service_order_number as os, c.actual_minutes as minutos, c.created_at::date as quando,
           c.created_at
    from public.service_cases c
    left join public.service_orders so on so.id = c.service_order_id
    where c.service_id = p_service_id and c.usable and c.actual_minutes > 0
    order by c.created_at desc
    limit 5
  ) x;

  return jsonb_build_object('tem_base', true, 'casos', v_n,
    'p50_min', round(v_p50), 'p80_min', round(v_p80),
    'contingencia_pct', least(30, greatest(5, round(((v_p80 - v_p50) / nullif(v_p50,0)) * 100))),
    'baseado_em', v_casos);
end;
$function$;

-- ── lev-32 · should_survey_service ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.should_survey_service(p_service_id uuid, p_client_id uuid DEFAULT NULL::uuid, p_vessel_id uuid DEFAULT NULL::uuid, p_valor numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_forcado boolean; v_casos integer; v_min integer; v_max integer;
  v_disp numeric; v_cliente_novo boolean := false;
  -- NOVO-lev-32: sem cast cru — texto malformado cai no padrão em vez de derrubar o painel.
  v_limiar numeric := coalesce(
    public.parse_valor_ptbr((select value from public.app_settings where key = 'survey_valor_limiar')), 3000);
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select coalesce(requires_survey, false) into v_forcado from public.services where id = p_service_id;

  select count(*), min(actual_minutes), max(actual_minutes) into v_casos, v_min, v_max
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_casos >= 2 and v_min > 0 then
    v_disp := round(((v_max - v_min)::numeric / v_min) * 100, 0);
  end if;

  if p_client_id is not null then
    select not exists (
      select 1 from public.service_orders
      where client_id = p_client_id and status in ('completed','invoiced')
    ) into v_cliente_novo;
  end if;

  return jsonb_build_object(
    'precisa', (coalesce(v_forcado,false) or coalesce(v_disp,0) > 30 or v_casos = 0
                or coalesce(p_valor,0) >= v_limiar or v_cliente_novo),
    'motivos', (
      select coalesce(jsonb_agg(m), '[]'::jsonb) from (
        select 'Serviço marcado como sempre exigindo levantamento' as m where coalesce(v_forcado,false)
        union all
        select 'Execuções anteriores variaram ' || v_disp || '% entre si' where coalesce(v_disp,0) > 30
        union all
        select 'Nenhuma execução registrada deste serviço' where v_casos = 0
        union all
        select 'Valor de ' || to_char(p_valor,'FM999G999D00') || ' acima do limiar de ' || to_char(v_limiar,'FM999G999D00')
          where coalesce(p_valor,0) >= v_limiar
        union all
        select 'Cliente ainda sem serviço concluído' where v_cliente_novo
      ) t),
    'casos_conhecidos', v_casos,
    'dispersao_pct', v_disp);
end;
$function$;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260910140000', 'funcoes_levantamento_lev_29_30_32')
on conflict (version) do nothing;
