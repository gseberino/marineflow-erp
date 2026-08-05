-- ═══════════════════════════════════════════════════════════════════════════
-- "Quem levou isso, levou aquilo"
--
-- O dono notou que há muito serviço onde o sistema poderia sugerir material,
-- "como dispositivos de proteção". O histórico já sabe: a Tela GX Touch entrou
-- em 5 das 5 ordens que tiveram o Cerbo GX; o Porta Fusível MIDI apareceu em 3
-- das 4 que tiveram o Kit de Cabos.
--
-- Isso não é a máquina adivinhando — é a própria casa, medida. Por isso a
-- evidência viaja junto da sugestão: "em 5 de 5 vezes". Quem lê julga o
-- número, não a opinião de um modelo.
--
-- O MÍNIMO IMPORTA. Com 50 ordens que têm material, um par que apareceu duas
-- vezes é coincidência com cara de padrão. O padrão é 3, e quem chamar pode
-- endurecer.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.related_materials(
  p_service_order_id uuid,
  p_min_juntos integer default 3)
returns table (
  product_id uuid,
  product_name text,
  unit text,
  sale_price numeric,
  por_causa_de text,
  juntos integer,
  de_total integer,
  pct integer)
language sql stable security invoker set search_path = public
as $fn$
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
  )
  -- distinct on (sugerido): um produto pode ser puxado por vários itens da
  -- ordem. Mostrar o mesmo material três vezes, uma por origem, transformaria
  -- a lista num quebra-cabeça — fica o vínculo mais forte.
  select distinct on (c.sugerido)
    p.id, p.name, p.unit, coalesce(p.sale_price, 0),
    base.name as por_causa_de,
    c.juntos, t.de_total,
    round(100.0 * c.juntos / nullif(t.de_total, 0))::integer as pct
  from companheiros c
  join total_base t on t.base = c.base
  join public.products p on p.id = c.sugerido
  join public.products base on base.id = c.base
  where c.juntos >= p_min_juntos
    and p.active
  order by c.sugerido, pct desc, c.juntos desc;
$fn$;

revoke all on function public.related_materials(uuid, integer) from public, anon;
grant execute on function public.related_materials(uuid, integer) to authenticated;

comment on function public.related_materials(uuid, integer) is
  'Material que costuma acompanhar o que já está na ordem, medido no histórico
   da casa. Traz a evidência (juntos/de_total/pct) porque é ela que se julga —
   sugestão sem contagem é palpite. Mínimo padrão de 3 ocorrências.';
